//===--- CSStep.cpp - Constraint Solver Steps -----------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// This file implements the \c SolverStep class and its related types,
// which is used by constraint solver to do iterative solving.
//
//===----------------------------------------------------------------------===//

#include "CSStep.h"
#include "TypeChecker.h"
#include "swift/AST/Types.h"
#include "swift/AST/TypeCheckRequests.h"
#include "swift/AST/GenericEnvironment.h"
#include "swift/Sema/ConstraintSystem.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;
using namespace swift;
using namespace constraints;

ComponentStep::Scope::Scope(ComponentStep &component)
    : CS(component.CS), Component(component) {
  TypeVars = std::move(CS.TypeVariables);

  for (auto *typeVar : component.TypeVars)
    CS.addTypeVariable(typeVar);

  auto &workList = CS.InactiveConstraints;
  workList.splice(workList.end(), *component.Constraints);

  SolverScope = new ConstraintSystem::SolverScope(CS);
  PrevPartialScope = CS.solverState->PartialSolutionScope;
  CS.solverState->PartialSolutionScope = SolverScope;
}

StepResult SplitterStep::take(bool prevFailed) {
  // "split" is considered a failure if previous step failed,
  // or there is a failure recorded by constraint system, or
  // system can't be simplified.
  if (prevFailed || CS.failedConstraint || CS.simplify())
    return done(/*isSuccess=*/false);

  SmallVector<std::unique_ptr<SolverStep>, 4> followup;
  // Try to run "connected components" algorithm and split
  // type variables and their constraints into independent
  // sub-systems to solve.
  computeFollowupSteps(followup);

  // If there is only one step, there is no reason to
  // try to merge solutions, "split" step should be considered
  // done and replaced by a single component step.
  if (followup.size() < 2)
    return replaceWith(std::move(followup.front()));

  /// Wait until all of the steps are done.
  return suspend(followup);
}

StepResult SplitterStep::resume(bool prevFailed) {
  // Restore the state of the constraint system to before split.
  CS.CG.setOrphanedConstraints(std::move(OrphanedConstraints));
  auto &workList = CS.InactiveConstraints;
  for (auto &component : Components)
    workList.splice(workList.end(), component);

  // If we came back to this step and previous (one of the components)
  // failed, it means that we can't solve this step either.
  if (prevFailed)
    return done(/*isSuccess=*/false);

  // Otherwise let's try to merge partial solutions together
  // and form a complete solution(s) for this split.
  return done(mergePartialSolutions());
}

void SplitterStep::computeFollowupSteps(
    SmallVectorImpl<std::unique_ptr<SolverStep>> &steps) {
  // Compute next steps based on that connected components
  // algorithm tells us is splittable.

  auto &CG = CS.getConstraintGraph();
  // Contract the edges of the constraint graph.
  CG.optimize();

  // Compute the connected components of the constraint graph.
  auto components = CG.computeConnectedComponents(CS.getTypeVariables());
  unsigned numComponents = components.size();
  if (numComponents < 2) {
    steps.push_back(std::make_unique<ComponentStep>(
        CS, 0, &CS.InactiveConstraints, Solutions));
    return;
  }

  if (CS.isDebugMode()) {
    auto &log = getDebugLogger();
    // Verify that the constraint graph is valid.
    CG.verify();

    log << "---Constraint graph---\n";
    CG.print(CS.getTypeVariables(), log);

    log << "---Connected components---\n";
    CG.printConnectedComponents(CS.getTypeVariables(), log);
  }

  // Take the orphaned constraints, because they'll go into a component now.
  OrphanedConstraints = CG.takeOrphanedConstraints();

  IncludeInMergedResults.resize(numComponents, true);
  Components.resize(numComponents);
  PartialSolutions = std::unique_ptr<SmallVector<Solution, 4>[]>(
      new SmallVector<Solution, 4>[numComponents]);

  // Add components.
  for (unsigned i : indices(components)) {
    unsigned solutionIndex = components[i].solutionIndex;

    // If there are no dependencies, build a normal component step.
    if (components[i].getDependencies().empty()) {
      steps.push_back(std::make_unique<ComponentStep>(
          CS, solutionIndex, &Components[i], std::move(components[i]),
          PartialSolutions[solutionIndex]));
      continue;
    }

    // Note that the partial results from any dependencies of this component
    // need not be included in the final merged results, because they'll
    // already be part of the partial results for this component.
    for (auto dependsOn : components[i].getDependencies()) {
      IncludeInMergedResults[dependsOn] = false;
    }

    // Otherwise, build a dependent component "splitter" step, which
    // handles all combinations of incoming partial solutions.
    steps.push_back(std::make_unique<DependentComponentSplitterStep>(
        CS, &Components[i], solutionIndex, std::move(components[i]),
        llvm::makeMutableArrayRef(PartialSolutions.get(), numComponents)));
  }

  assert(CS.InactiveConstraints.empty() && "Missed a constraint");
}

namespace {
  /// Retrieve the size of a container.
  template<typename Container>
  unsigned getSize(const Container &container) {
    return container.size();
  }

  /// Retrieve the size of a container referenced by a pointer.
  template<typename Container>
  unsigned getSize(const Container *container) {
    return container->size();
  }

  /// Identity getSize() for cases where we are working with a count.
  unsigned getSize(unsigned size) {
    return size;
  }

  /// Compute the next combination of indices into the given array of
  /// containers.
  /// \param containers Containers (each of which must have a `size()`) in
  /// which the indices will be generated.
  /// \param indices The current indices into the containers, which will
  /// be updated to represent the next combination.
  /// \returns true to indicate that \c indices contains the next combination,
  /// or \c false to indicate that there are no combinations left.
  template<typename Container>
  bool nextCombination(ArrayRef<Container> containers,
                       MutableArrayRef<unsigned> indices) {
    assert(containers.size() == indices.size() &&
           "Indices should have been initialized to the same size with 0s");
    unsigned numIndices = containers.size();
    for (unsigned n = numIndices; n > 0; --n) {
      ++indices[n - 1];

      // If we haven't run out of solutions yet, we're done.
      if (indices[n - 1] < getSize(containers[n - 1]))
        break;

      // If we ran out of solutions at the first position, we're done.
      if (n == 1) {
        return false;
      }

      // Zero out the indices from here to the end.
      for (unsigned i = n - 1; i != numIndices; ++i)
        indices[i] = 0;
    }

    return true;
  }
}

bool SplitterStep::mergePartialSolutions() const {
  assert(Components.size() >= 2);

  // Compute the # of partial solutions that will be merged for each
  // component. Components that shouldn't be included will get a count of 1,
  // an we'll skip them later.
  auto numComponents = Components.size();
  SmallVector<unsigned, 2> countsVec;
  countsVec.reserve(numComponents);
  for (unsigned idx : range(numComponents)) {
    countsVec.push_back(
        IncludeInMergedResults[idx] ? PartialSolutions[idx].size() : 1);
  }

  // Produce all combinations of partial solutions.
  ArrayRef<unsigned> counts = countsVec;
  SmallVector<unsigned, 2> indices(numComponents, 0);
  bool anySolutions = false;
  size_t solutionMemory = 0;
  do {
    // Create a new solver scope in which we apply all of the relevant partial
    // solutions.
    ConstraintSystem::SolverScope scope(CS);
    for (unsigned i : range(numComponents)) {
      if (!IncludeInMergedResults[i])
        continue;

      CS.applySolution(PartialSolutions[i][indices[i]]);
    }

    // This solution might be worse than the best solution found so far.
    // If so, skip it.
    if (!CS.worseThanBestSolution()) {
      // Finalize this solution.
      auto solution = CS.finalize();
      solutionMemory += solution.getTotalMemory();
      if (CS.isDebugMode())
        getDebugLogger() << "(composed solution " << CS.CurrentScore << ")\n";

      // Save this solution.
      Solutions.push_back(std::move(solution));
      anySolutions = true;
    }

    // Since merging partial solutions can go exponential, make sure we didn't
    // pass the "too complex" thresholds including allocated memory and time.
    if (CS.getExpressionTooComplex(solutionMemory))
      return false;

  } while (nextCombination(counts, indices));

  return anySolutions;
}

StepResult DependentComponentSplitterStep::take(bool prevFailed) {
  // "split" is considered a failure if previous step failed,
  // or there is a failure recorded by constraint system, or
  // system can't be simplified.
  if (prevFailed || CS.getFailedConstraint() || CS.simplify())
    return done(/*isSuccess=*/false);

  // Figure out the sets of partial solutions that this component depends on.
  SmallVector<const SmallVector<Solution, 4> *, 2> dependsOnSets;
  for (auto index : Component.getDependencies()) {
    dependsOnSets.push_back(&AllPartialSolutions[index]);
  }

  // Produce all combinations of partial solutions for the inputs.
  SmallVector<std::unique_ptr<SolverStep>, 4> followup;
  SmallVector<unsigned, 2> indices(Component.getDependencies().size(), 0);
  auto dependsOnSetsRef = llvm::makeArrayRef(dependsOnSets);
  do {
    // Form the set of input partial solutions.
    SmallVector<const Solution *, 2> dependsOnSolutions;
    for (auto index : swift::indices(indices)) {
      dependsOnSolutions.push_back(&(*dependsOnSets[index])[indices[index]]);
    }

    followup.push_back(
        std::make_unique<ComponentStep>(CS, Index, Constraints, Component,
                                         std::move(dependsOnSolutions),
                                         Solutions));
  } while (nextCombination(dependsOnSetsRef, indices));

  /// Wait until all of the component steps are done.
  return suspend(followup);
}

StepResult DependentComponentSplitterStep::resume(bool prevFailed) {
  return done(/*isSuccess=*/!Solutions.empty());
}

void DependentComponentSplitterStep::print(llvm::raw_ostream &Out) {
  Out << "DependentComponentSplitterStep for dependencies on [";
  interleave(
      Component.getDependencies(), [&](unsigned index) { Out << index; },
      [&] { Out << ", "; });
  Out << "]\n";
}

StepResult ComponentStep::take(bool prevFailed) {
  // One of the previous components created by "split"
  // failed, it means that we can't solve this component.
  if ((prevFailed && DependsOnPartialSolutions.empty()) ||
      CS.getExpressionTooComplex(Solutions))
    return done(/*isSuccess=*/false);

  // Setup active scope, only if previous component didn't fail.
  setupScope();

  // If there are any dependent partial solutions to compose, do so now.
  if (!DependsOnPartialSolutions.empty()) {
    for (auto partial : DependsOnPartialSolutions) {
      CS.applySolution(*partial);
    }

    // Activate all of the one-way constraints.
    SmallVector<Constraint *, 4> oneWayConstraints;
    for (auto &constraint : CS.InactiveConstraints) {
      if (constraint.isOneWayConstraint())
        oneWayConstraints.push_back(&constraint);
    }
    for (auto constraint : oneWayConstraints) {
      CS.activateConstraint(constraint);
    }

    // Simplify again.
    if (CS.failedConstraint || CS.simplify())
      return done(/*isSuccess=*/false);
  }

  /// Try to figure out what this step is going to be,
  /// after the scope has been established.
  auto *disjunction = CS.selectDisjunction();
  auto bestBindings = CS.determineBestBindings();

  if (bestBindings &&
      (!disjunction || bestBindings->favoredOverDisjunction(disjunction))) {
    // Produce a type variable step.
    return suspend(
        std::make_unique<TypeVariableStep>(*bestBindings, Solutions));
  } else if (disjunction) {
    // Produce a disjunction step.
    return suspend(
        std::make_unique<DisjunctionStep>(CS, disjunction, Solutions));
  } else if (!CS.solverState->allowsFreeTypeVariables() &&
             CS.hasFreeTypeVariables()) {
    // If there are no disjunctions or type variables to bind
    // we can't solve this system unless we have free type variables
    // allowed in the solution.
    return finalize(/*isSuccess=*/false);
  }

  // If we don't have any disjunction or type variable choices left, we're done
  // solving. Make sure we don't have any unsolved constraints left over, using
  // report_fatal_error to make sure we trap in release builds instead of
  // potentially miscompiling.
  if (!CS.ActiveConstraints.empty()) {
    CS.print(llvm::errs());
    llvm::report_fatal_error("Active constraints left over?");
  }
  if (!CS.solverState->allowsFreeTypeVariables()) {
    if (!CS.InactiveConstraints.empty()) {
      CS.print(llvm::errs());
      llvm::report_fatal_error("Inactive constraints left over?");
    }
    if (CS.hasFreeTypeVariables()) {
      CS.print(llvm::errs());
      llvm::report_fatal_error("Free type variables left over?");
    }
  }

  // If this solution is worse than the best solution we've seen so far,
  // skip it.
  if (CS.worseThanBestSolution())
    return finalize(/*isSuccess=*/false);

  // If we only have relational or member constraints and are allowing
  // free type variables, save the solution.
  for (auto &constraint : CS.InactiveConstraints) {
    switch (constraint.getClassification()) {
    case ConstraintClassification::Relational:
    case ConstraintClassification::Member:
      continue;
    default:
      return finalize(/*isSuccess=*/false);
    }
  }

  auto solution = CS.finalize();
  if (CS.isDebugMode())
    getDebugLogger() << "(found solution " << getCurrentScore() << ")\n";

  Solutions.push_back(std::move(solution));
  return finalize(/*isSuccess=*/true);
}

StepResult ComponentStep::finalize(bool isSuccess) {
  // If this was a single component, there is nothing to be done,
  // because it represents the whole constraint system at some
  // point of the solver path.
  if (IsSingle)
    return done(isSuccess);

  // Rewind all modifications done to constraint system.
  ComponentScope.reset();

  if (CS.isDebugMode()) {
    auto &log = getDebugLogger();
    log << (isSuccess ? "finished" : "failed") << " component #" << Index
        << ")\n";
  }

  // If we came either back to this step and previous
  // (either disjunction or type var) failed, it means
  // that component as a whole has failed.
  if (!isSuccess)
    return done(/*isSuccess=*/false);

  assert(!Solutions.empty() && "No Solutions?");

  // For each of the partial solutions, subtract off the current score.
  // It doesn't contribute.
  for (auto &solution : Solutions)
    solution.getFixedScore() -= OriginalScore;

  // Restore the original best score.
  CS.solverState->BestScore = OriginalBestScore;

  // When there are multiple partial solutions for a given connected component,
  // rank those solutions to pick the best ones. This limits the number of
  // combinations we need to produce; in the common case, down to a single
  // combination.
  filterSolutions(Solutions, /*minimize=*/true);
  return done(/*isSuccess=*/true);
}

void TypeVariableStep::setup() {
  ++CS.solverState->NumTypeVariablesBound;
  if (CS.isDebugMode()) {
    PrintOptions PO;
    PO.PrintTypesForDebugging = true;
    auto &log = getDebugLogger();

    auto initialBindings = Producer.getCurrentBindings();
    log << "Initial bindings: ";
    interleave(
        initialBindings.begin(), initialBindings.end(),
        [&](const Binding &binding) {
          log << TypeVar->getString(PO)
              << " := " << binding.BindingType->getString(PO);
        },
        [&log] { log << ", "; });

    log << '\n';
  }
}

bool TypeVariableStep::attempt(const TypeVariableBinding &choice) {
  ++CS.solverState->NumTypeVariableBindings;

  if (choice.hasDefaultedProtocol())
    SawFirstLiteralConstraint = true;

  // Try to solve the system with typeVar := type
  return choice.attempt(CS);
}

StepResult TypeVariableStep::resume(bool prevFailed) {
  assert(ActiveChoice);

  // If there was no failure in the sub-path it means
  // that active binding has a solution.
  AnySolved |= !prevFailed;

  bool shouldStop = shouldStopAfter(ActiveChoice->second);
  // Rewind back all of the changes made to constraint system.
  ActiveChoice.reset();

  if (CS.isDebugMode())
    getDebugLogger() << ")\n";

  // Let's check if we should stop right before
  // attempting any new bindings.
  if (shouldStop)
    return done(/*isSuccess=*/AnySolved);

  // Attempt next type variable binding.
  return take(prevFailed);
}

StepResult DisjunctionStep::resume(bool prevFailed) {
  // If disjunction step is re-taken and there should be
  // active choice, let's see if it has be solved or not.
  assert(ActiveChoice);

  // If choice (sub-path) has failed, it's okay, other
  // choices have to be attempted regardless, since final
  // decision could be made only after attempting all
  // of the choices, so let's just ignore failed ones.
  if (!prevFailed) {
    auto &choice = ActiveChoice->second;
    auto score = getBestScore(Solutions);

    if (!choice.isGenericOperator() && choice.isSymmetricOperator()) {
      if (!BestNonGenericScore || score < BestNonGenericScore) {
        BestNonGenericScore = score;
        if (shouldSkipGenericOperators()) {
          // The disjunction choice producer shouldn't do the work
          // to partition the generic operator choices if generic
          // operators are going to be skipped.
          Producer.setNeedsGenericOperatorOrdering(false);
        }
      }
    }

    AnySolved = true;
    // Remember the last successfully solved choice,
    // it would be useful when disjunction is exhausted.
    LastSolvedChoice = {choice, *score};
  }

  // Rewind back the constraint system information.
  ActiveChoice.reset();

  if (CS.isDebugMode())
    getDebugLogger() << ")\n";

  // Attempt next disjunction choice (if any left).
  return take(prevFailed);
}

bool IsDeclRefinementOfRequest::evaluate(Evaluator &evaluator,
                                          ValueDecl *declA,
                                          ValueDecl *declB) const {
  auto *typeA = declA->getInterfaceType()->getAs<GenericFunctionType>();
  auto *typeB = declB->getInterfaceType()->getAs<GenericFunctionType>();

  if (!typeA || !typeB)
    return false;

  auto genericSignatureA = typeA->getGenericSignature();
  auto genericSignatureB = typeB->getGenericSignature();

  // Substitute generic parameters with their archetypes in each generic function.
  Type substTypeA = typeA->substGenericArgs(
      genericSignatureA->getGenericEnvironment()->getForwardingSubstitutionMap());
  Type substTypeB = typeB->substGenericArgs(
      genericSignatureB->getGenericEnvironment()->getForwardingSubstitutionMap());

  // Attempt to substitute archetypes from the second type with archetypes in the
  // same structural position in the first type.
  TypeSubstitutionMap substMap;
  substTypeB = substTypeB->substituteBindingsTo(substTypeA,
      [&](ArchetypeType *origType, CanType substType,
          ArchetypeType *, ArrayRef<ProtocolConformanceRef>) -> CanType {
    auto interfaceTy =
        origType->getInterfaceType()->getCanonicalType()->getAs<SubstitutableType>();

    // Make sure any duplicate bindings are equal to the one already recorded.
    // Otherwise, the substition has conflicting generic arguments.
    auto bound = substMap.find(interfaceTy);
    if (bound != substMap.end() && !bound->second->isEqual(substType))
      return CanType();

    substMap[interfaceTy] = substType;
    return substType;
  });

  if (!substTypeB)
    return false;

  auto result = TypeChecker::checkGenericArguments(
      declA->getDeclContext(), SourceLoc(), SourceLoc(), typeB,
      genericSignatureB->getGenericParams(),
      genericSignatureB->getRequirements(),
      QueryTypeSubstitutionMap{ substMap });

  if (result != RequirementCheckResult::Success)
    return false;

  return substTypeA->isEqual(substTypeB);
}

bool TypeChecker::isDeclRefinementOf(ValueDecl *declA, ValueDecl *declB) {
  return evaluateOrDefault(declA->getASTContext().evaluator,
                           IsDeclRefinementOfRequest{ declA, declB },
                           false);
}

bool DisjunctionStep::shouldSkip(const DisjunctionChoice &choice) const {
  auto &ctx = CS.getASTContext();

  auto skip = [&](std::string reason) -> bool {
    if (CS.isDebugMode()) {
      auto &log = getDebugLogger();
      log << "(skipping " + reason + " ";
      choice.print(log, &ctx.SourceMgr);
      log << '\n';
    }

    return true;
  };


  // Skip disabled overloads in the diagnostic mode if they do not have a
  // fix attached to them e.g. overloads where labels didn't match up.
  if (choice.isDisabled() && !(CS.shouldAttemptFixes() && choice.hasFix()))
    return skip("disabled");

  // Skip unavailable overloads (unless in dignostic mode).
  if (choice.isUnavailable() && !CS.shouldAttemptFixes())
    return skip("unavailable");

  if (ctx.TypeCheckerOpts.DisableConstraintSolverPerformanceHacks)
    return false;

  // If the solver already found a solution with a better overload choice that
  // can be unconditionally substituted by the current choice, skip the current
  // choice.
  if (LastSolvedChoice && LastSolvedChoice->second == getCurrentScore() &&
      choice.isGenericOperator()) {
    auto *declA = LastSolvedChoice->first->getOverloadChoice().getDecl();
    auto *declB = static_cast<Constraint *>(choice)->getOverloadChoice().getDecl();

    if (declA->getBaseIdentifier().isArithmeticOperator() &&
        TypeChecker::isDeclRefinementOf(declA, declB)) {
      return skip("subtype");
    }
  }

  // If the solver already found a solution with a choice that did not
  // introduce any conversions (i.e., the score is not worse than the
  // current score), we can skip any generic operators with conformance
  // requirements that are not satisfied by any known argument types.
  auto argFnType = CS.getAppliedDisjunctionArgumentFunction(Disjunction);
  auto checkRequirementsEarly = [&]() -> bool {
    auto bestScore = getBestScore(Solutions);
    if (!(bestScore && choice.isGenericOperator() && argFnType))
      return false;

    auto currentScore = getCurrentScore();
    for (unsigned i = 0; i < NumScoreKinds; ++i) {
      if (i == SK_NonDefaultLiteral)
        continue;

      if (bestScore->Data[i] > currentScore.Data[i])
        return false;
    }

    return true;
  };
  if (checkRequirementsEarly()) {
    Constraint *constraint = choice;
    auto *decl = constraint->getOverloadChoice().getDecl();
    if (decl->getBaseIdentifier().isArithmeticOperator()) {
      auto *useDC = constraint->getOverloadUseDC();
      auto choiceType = CS.getEffectiveOverloadType(
          constraint->getLocator(), constraint->getOverloadChoice(),
          /*allowMembers=*/true, useDC);
      auto choiceFnType = choiceType->getAs<FunctionType>();
      auto genericFnType = decl->getInterfaceType()->getAs<GenericFunctionType>();
      auto signature = genericFnType->getGenericSignature();

      for (auto argParamPair : llvm::zip(argFnType->getParams(),
                                         choiceFnType->getParams())) {
        auto argType = std::get<0>(argParamPair).getPlainType();
        auto paramType = std::get<1>(argParamPair).getPlainType();

        // Only check argument types with no type variables that will be matched
        // against a plain type parameter.
        argType = argType->getCanonicalType()->getWithoutSpecifierType();
        if (argType->hasTypeVariable() || !paramType->isTypeParameter())
          continue;

        for (auto *protocol : signature->getRequiredProtocols(paramType)) {
          if (!TypeChecker::conformsToProtocol(argType, protocol, useDC))
            return skip("unsatisfied");
        }
      }
    }
  }

  // Don't attempt to solve for generic operators if we already have
  // a non-generic solution.

  // FIXME: Less-horrible but still horrible hack to attempt to
  //        speed things up. Skip the generic operators if we
  //        already have a solution involving non-generic operators,
  //        but continue looking for a better non-generic operator
  //        solution.
  if (shouldSkipGenericOperators() && choice.isGenericOperator()) {
    return skip("generic");
  }

  return false;
}

bool DisjunctionStep::shouldStopAt(const DisjunctionChoice &choice) const {
  if (!LastSolvedChoice)
    return false;

  auto *lastChoice = LastSolvedChoice->first;
  auto delta = LastSolvedChoice->second - getCurrentScore();
  bool hasUnavailableOverloads = delta.Data[SK_Unavailable] > 0;
  bool hasFixes = delta.Data[SK_Fix] > 0;
  bool hasAsyncMismatch = delta.Data[SK_AsyncInSyncMismatch] > 0;
  auto isBeginningOfPartition = choice.isBeginningOfPartition();

  // Attempt to short-circuit evaluation of this disjunction only
  // if the disjunction choice we are comparing to did not involve:
  //   1. selecting unavailable overloads
  //   2. result in fixes being applied to reach a solution
  //   3. selecting an overload that results in an async/sync mismatch
  return !hasUnavailableOverloads && !hasFixes && !hasAsyncMismatch &&
         (isBeginningOfPartition ||
          shortCircuitDisjunctionAt(choice, lastChoice));
}

bool swift::isSIMDOperator(ValueDecl *value) {
  if (!value)
    return false;

  auto func = dyn_cast<FuncDecl>(value);
  if (!func)
    return false;

  if (!func->isOperator())
    return false;

  auto nominal = func->getDeclContext()->getSelfNominalTypeDecl();
  if (!nominal)
    return false;

  if (nominal->getName().empty())
    return false;

  return nominal->getName().str().startswith_lower("simd");
}

bool DisjunctionStep::shortCircuitDisjunctionAt(
    Constraint *currentChoice, Constraint *lastSuccessfulChoice) const {
  auto &ctx = CS.getASTContext();

  // Anything without a fix is better than anything with a fix.
  if (currentChoice->getFix() && !lastSuccessfulChoice->getFix())
    return true;

  if (ctx.TypeCheckerOpts.DisableConstraintSolverPerformanceHacks)
    return false;

  if (auto restriction = currentChoice->getRestriction()) {
    // Non-optional conversions are better than optional-to-optional
    // conversions.
    if (*restriction == ConversionRestrictionKind::OptionalToOptional)
      return true;

    // Array-to-pointer conversions are better than inout-to-pointer
    // conversions.
    if (auto successfulRestriction = lastSuccessfulChoice->getRestriction()) {
      if (*successfulRestriction == ConversionRestrictionKind::ArrayToPointer &&
          *restriction == ConversionRestrictionKind::InoutToPointer)
        return true;
    }
  }

  // Implicit conversions are better than checked casts.
  if (currentChoice->getKind() == ConstraintKind::CheckedCast)
    return true;

  return false;
}

bool DisjunctionStep::attempt(const DisjunctionChoice &choice) {
  ++CS.solverState->NumDisjunctionTerms;

  // If the disjunction requested us to, remember which choice we
  // took for it.
  if (auto *disjunctionLocator = getLocator()) {
    auto index = choice.getIndex();
    recordDisjunctionChoice(disjunctionLocator, index);

    // Implicit unwraps of optionals are worse solutions than those
    // not involving implicit unwraps.
    if (!disjunctionLocator->getPath().empty()) {
      auto kind = disjunctionLocator->getPath().back().getKind();
      if (kind == ConstraintLocator::ImplicitlyUnwrappedDisjunctionChoice ||
          kind == ConstraintLocator::DynamicLookupResult) {
        assert(index == 0 || index == 1);
        if (index == 1)
          CS.increaseScore(SK_ForceUnchecked);
      }
    }
  }

  return choice.attempt(CS);
}