define i32 @sum(i32 %a, i32 %b) {
    %res = add i32 %a, %b
    ret i32 %res
}

define i32 @main() {
    %exit_code = call i32 @sum(i32 15, i32 27)
    ret i32 %exit_code
}