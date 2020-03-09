## Single data stack

Instead of preallocating a stack with alloca per call, use a single big shared stack array.

This completely removes the need to know the register frame size upfront, which makes both the generator and
interpreter much simpler.
