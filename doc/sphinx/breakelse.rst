===============================================
`breakelse`: When Compiler Developers Get Bored
===============================================

Good morning, internet! In programming languages, it's a common issue that we want to both *test* a value
and *use* the value.

For example:

.. code-block:: D

    if (key in associativeArray)
    {
        auto value = associativeArray[key];
    }

I've been trying to find a better way to do this for my programming language, `Neat <https://neat-lang.github.io>`_,
for a while now. In `D <https://dlang.org>`_, the language that Neat inherits most of its syntax from, we can both
declare a value and test it for `truthiness <https://en.wikipedia.org/wiki/Truthiness>`_ with this syntax:

.. code-block:: D

    if (auto var = function())
    {
    }

But many types, such as associative-array values, don't have a convenient truthiness state associated with them,
and in a static language we can't just return nil.

Anyway, since `soatok <https://soatok.blog/b/>`_ and
`Xe <https://xeiaso.net/blog/>`_ I feel it's become difficult to be taken seriously in the tech industry if your
blog doesn't have interjections from characters with furry icons.
Because I'm not exactly great at theory of mind, or at guessing what a reader
would already know, I
asked around on IRC and got `gurkenglas <https://gurkenglas.com>`_ and another participant to play the role of
character with the furry icon.
Thanks a bunch! Say hello!

.. xe-quote:: gurkenglas neutral

    hello! is it okay if i just guess what words like "auto" and "soatok" mean?

As the helpful audience surrogate, ask whenever something is unclear!
In this case, `auto` is a keyword that Neat takes from D that just means "the variable has the type of its initializer".
soatok, of `Dhole Moments <https://soatok.blog/b/>`_,
is heavily responsible for popularizing the mix of furry and technical content
that this article is riffing off of, though the particular
format is mostly borrowed from `Xe Iaso <https://xeiaso.net/blog/>`_.

Our second participant asked only to be represented by a shoebill. Sadly-

.. xe-quote:: shoebill neutral

    Hi!

\- Stable Diffusion was not ... *entirely* up to the job of a shoebill furry avatar.
It had to go to other animals to find a reference for the elongated skull shape.
So we will graciously ignore the dog snout on a bird.

Okay, format now established, let's get to the actual topic. A related question that's been driving me for a while
is... what exactly is the correct return type of `find`? Traditionally in C-likes, we're returning -1 if the element
was not found, but that's terrible for many reasons.

.. xe-quote:: gurkenglas suggesting

    well of course you pass it a continuation

Oy, we're still writing C-likes here. No silly buggers with lambdas. No, the actual problem is that `-1`,
or `0xffff_ffff`, is an entirely valid position for your element to appear in the array.
Well, if the array takes up literally the entire available memory.

.. xe-quote:: gurkenglas suggesting

    Well what if you

.. code-block:: D

    mut string data = file.readText;
    while (auto line = data.eat("(.*)\n"))
    {
        ...
    }

I mean, sure.

But then you have the exact same issue: `eat` has to return a data type that both describes "a line of text" and
"the possibility that no more line can be found".

.. xe-quote:: shoebill considering

    I think the better C way is to use output pointer parameters, you do `if (find(query, &output))`...
    So it returns a boolean if it found the thing, and writes the result in the pointer.

Yep, that works, and I do have tuple return values. [#]_ In fact, for a while I was
resigned to having a special return type from `find` that `if` could split up into success indicator and result value.
I think I've found a better way, and I will go into it later.

This challenge turns up everywhere in API design. In D, for instance, we'd write `if (auto value = key in assocArray)`,
but then D just sets value to a pointer, a naturally nullable type. And even though if we're in the `if`, we know the
pointer can never be `null`, we have to carry its pointerness around with us for no reason.

Some languages solve this problem by allowing every value to be `null`, or `nil`, or `None`.
Those languages are bad and after this paragraph I will speak no more of them, but they did bring us
a relevant innovation: the conditional-access operator, `?.`.
See, if every type can be `null`, you can just say "well, if the value is `null`, we keep it `null`; otherwise,
we perform an operation."

That's cool! But at the end of the chain, you will still need to terminate your chain in a type
that can have either a value or `null`. And because we want to be able to both test if the operation succeeds,
and use the resulting value, that just puts us back where we started.

.. xe-quote:: shoebill aghast

    So okay hold on, I guess `null` is reserved for the did-not-work-out thing, so if we get `null`,
    can't we just declare that the operation failed and there's no value to do anything with,
    and if we get anything non-`null`, we both know it succeeded and have a value to play with?

Grrr! Okay, a bit more about why I dislike making every type nullable then. Remember, you asked for this lecture.

.. raw:: html

    <span class="rant-gets-smaller">
    Types should describe the domain of a value. A language where every type can be implicitly nullable is in effect
    <span>
    saying that literally no operation can be trusted. In a way, the whole point of a typesystem is to make conversion
    <span>
    failures visible early. A language where everything may be null doesn't just say that every operation can fail -
    <span>
    even the ones that clearly don't - it also destroys your ability to do anything about it. You either ignore the
    <span>
    possibility of null until it comes up - and the language has to let you do that - or you check every value on every
    <span>
    access. This teaches programmers that "defensive programming" is "just conditional-operator all the things", thus
    <span>
    ironically destroying their ability to notice when a real issue happens. Instead of moving the errors earlier,
    <span>
    we've moved them later - possibly much later! This defeats the entire reason we decided to have a strong typesystem
    <span>
    in the first place! In conclusion, null is the billion dollar mistake and I will have no part of it.
    <span>
    Non-nullable pointers by default, yo.
    </span></span></span></span></span></span></span></span></span></span>

.. xe-quote:: shoebill

    Right, we want to signal failure with a value that doesn't clobber anything else, but we don't want every point of
    code to have "oh, and it could be Something Else, better watch out for that" going on.

Yep, exactly. And that's why I'm not adding conditional access operators.

----

Anyway, for a while I considered having special handling for a return type of `(size_t | :else) find()`.
That is, `if` would see that there was a possibility of an `:else` return type, and use this opportunity to jump
to the `else` block instead of declaring a variable. But-

.. xe-quote:: gurkenglas unimpressed

    ...

Huh, I was sure you'd have questions about that syntax.

.. xe-quote:: gurkenglas unimpressed

    i'm a Haskell programmer,
    i know what a `sumtype <https://en.wikipedia.org/wiki/Tagged_union>`_ is.
    keep going

.. xe-quote:: shoebill aghast

    Okay, if you're too good for it, I'll ask! What's all this bar-colon-stuff? `|`, `:this`

Whew, good. Okay, so there's two things here. First, `(A | B)` is a sumtype.
It's a type syntax for "a type that can be either A or B". It's like a union, but it also stores which
field of the union is set.

Then, `:token` is just a unique value that's only equal to itself.
Basically, it's a keyword value. You can write `:token VAR = :token;` and that's the only value that
variable can ever have. (You can reassign it, but only if the value you assign is also `:token`.)

The point is that it acts as an ad-hoc marker for a possible outcome in the sumtype without taking up space of its own.

.. xe-quote:: shoebill

    Right, like Lisp `'symbols`.

Yes, exactly!

But - the basic problem with this return type for `find` is that it cannot easily be chained.
(That is, you cannot keep working with the maybe-missing value.)
With `find`, the operation that we test for is usually the last in a chain.
With a language where every value is nullable, we can just keep chaining with `?.` and `?()`.

But let's take a slightly different API above.

.. code-block:: D

    if (auto line = data.eatLine().strip())
    {
    }

Well, what exactly is the parameter type of `strip` here?
If `eatLine` returned a `string`, then `strip` would make sense, but we'd lose the "maybe no line was found" check.
If eatLine returned `(string | :else)`, the variable assignment would work, but the strip call wouldn't.
And sure, we could write

.. code-block:: D

    if (auto line = data.eatLine().case(string s: s.strip()))

But that's looking a lot more unwieldy than `eatLine()?.strip()` did.

.. xe-quote:: shoebill

    Okay hold on and let me try to parse that. You read a line from wherever and...  What's `case` again?

Okay, so if we have `eatLine()` typed as `(string | :else)`, that expresses
"we can either parse a line or not, for whatever reason". This sumtype effectively tells `if`:
"You can either declare a string variable, or don't bother entering the `if` block."

Then, `case` lets us react to only one case of the sumtype. For instance, `case(string s: X)` replaces
the string half of the sumtype with `X`, whatever its type; `:else` remains unchanged.

.. xe-quote:: shoebill considering

    So you want to do a sequence of stuff where you can fail at any line, and you don't want the
    annoying extra work of manually threading the failure case everywhere. This sounds a lot like one use case for
    Haskell monads when I was trying to figure those out.

Hah! I was waiting for somebody to bring those up.

It sure seems like the problem is one of syntax, right? In fact, you can even think of `null` as something like
the `Maybe` monad, with the conditional-access operations being curried versions of `apply`... Ahem.

So if you're saying that `eatLine` returns a conditional type, that may have a failure case, then we
want to take the success case only and apply `strip` to it, and then package things back up into a
conditional type that we can finally feed into the `if`.

However, I think that's a bad idea, or at least not as good as it could be, for reasons that have to do with the
fundamental difference between imperative and expression languages. But before I go into those, a diversion!

Let's ask a seemingly-unrelated question. If you're in a loop, you can break out of that loop or continue
from the beginning. Why exactly can you not break out of an if body?

For instance, say we had a keyword `breakelse`:

.. code-block:: D

    if (cond)
    {
        ...
        breakelse;
        ...
    }
    else
    {
        // breakelse jumps here
    }

It should do exactly what `break` does in a loop: jump to the end of the current loop block.
It just seems a weird omission.

I mean, stop me if you've seen code like this before:

.. code-block:: D

    if (auto var = op)
    {
        if (auto var2 = op(var))
        {
            if (auto var3 = op(var2))
            {

That's a blatant failure to keep functions flat, but there doesn't seem to be another way to do it
if we want to avoid making every type nullable. And it forces us to introduce a lot of variables that we
don't care about beyond one operation.

.. xe-quote:: gurkenglas looking

    i've seen it. does each of them have their own else block?

Usually, they just fall back down to the initial `if` block and then the function continues.

Anyway, you see my thinking, right? It seems what would help us is some way to "early abort" from the if condition.

.. xe-quote:: gurkenglas neutral

    You seem to be reinventing exceptions.

Exceptions are actually a good analogue for the data flow here. We have a `try` block, the `if`, that wants to do
a lot of operations, some of which will fail, but which are all conveyed into the same error-recovery block, the `else`.
However, exceptions are expensive.

What we really want is a way to write code like this:

.. code-block:: D

    if (auto var = op)
    {
        auto var2 = op(var);
        if (var2) breakelse;
        auto var3 = op(var2);
        if (!var3) breakelse;
        ...
    }

But `breakelse` doesn't actually seem to be very useful for that! In fact, that
example doesn't even work because of the nested ifs.

.. xe-quote:: shoebill considering

    Right, usually `break` is guarded by `if`, but if `breakelse` breaks from an `if`,
    then it's going to be a useless op by default...

The thing is that in this example, you are seeing that keyword at its very worst, most ill-placed.
I've been introducing it for this, but it's not actually really intended to appear free-standing in a function.
It's intended to appear in the if *expression,* and it's intended to allow us to abort it early.

If we just go all the way to our goal and chain these operations into one expression:

.. code-block:: D

    if (auto var3 = op.case(:else: breakelse)
        .op2.case(:else: breakelse)
        .op3.case(:else: breakelse))
    {
    }
    else
    {
    }

(Yes, `breakelse` is an expression. All nonlocal exits are expressions.)

So while it didn't work very well in the long block form, once we shift it into the if expression,
it reveals its true purpose.

.. xe-quote:: gurkenglas idea

    you sure are smuggling lots of Haskell patterns into your readership

It is sort of similar to `do notation <https://en.wikibooks.org/wiki/Haskell/do_notation>`_, isn't it.

But this is where I finally circle all the way back to `Maybe`, `Option`, `Nullable`, `null` and all its variants.
These constructs all have some version of the same fundamental issue that they force you into two different modes of access.
You have "normal operations" - `a.b.c` - and you have "propagating operations" - `a ?.b ?.c`, or
`a.apply(&.b).apply(&.c)`, or whatever the syntax is in Haskell for applying a function to the contents
of a monad.
Only at the end of the chain we admit what we really cared about - "did the operation succeed, and what was its value?"

So the payoff is on a typesystem level. if we continue in the test, past the `breakelse` and into the if block,
we can just assume that the type is the successful one - if it wasn't, we'd have left early. We *don't* have to
carry `:else` with us all the way: we can *immediately* say: "if this is `:else`, we are not interested
in entering the `if` block" and drop it from the type of the expression chain right then and there.

Because we're an imperative language, we don't just have types *or* clever syntax. We can use explicit control flow,
imperative languages' secret superpower, to make our lives easier.

.. xe-quote:: gurkenglas unimpressed

    are you sure this doesn't end up as expensive as exceptions? it seems to be as powerful.

The nice thing is that at the compiler level this is literally a goto. At the hardware level
we really are just jumping to the error handling block, ie. past the if. Natively,
it really is as cheap as `if`/`else`.

Let's look at another example. Earlier we had this code:

.. code-block:: D

    if (string line = eatLine().case(string s: s.strip()))

So `if` recognizes that the resulting type has an `:else` case and goes to `else` if it is set.

But what if we reversed it?

.. code-block:: D

    if (string line = eatLine().case(:else: breakelse))

.. xe-quote:: shoebill considering

    So let me try to follow what's going on in the second example...

    You try to read a line, and are ready to assign to a variable, you have the `.case` doing a partial match,
    and it is set to match the `:else` variant, which means no string obtained,
    and then you go for the `if`-statement-busting `breakelse` magic.

    And otherwise you got the assuredly not-`:else` line ready for stuff being done to it in the `if` statement body.

Yep, exactly! And because the type of `breakelse`, just like every nonlocal exit, is `bottom`,
this drops the `:else` type out of the sumtype, leaving only `string`.

.. xe-quote:: shoebill

    `bottom` was the weird "this never evaluates" type that you never write in your code but you use to describe
    stuff when you want everything to fit in a type system framework, right?

Yep! And because `breakelse` goes somewhere ... "else", heh, when you look at it as an expression,
its value can never be computed. (The same thing happens with `break`, `continue` and `return`.)

And here's the kicker: the type of that expression, after the closing parenthesis, is just `string`!

In other words, as soon as we see the possibility that the result could be `:else`,
we leave the if condition right then and there. And `if` doesn't even have to do anything: if it gets a value,
it just declares a variable - the value is just `string`, because `string` is the only value that
remains in the expression locally.

And because the type is `string`, we can just call `strip()` on it directly!

.. code-block:: D

    if (string line = eatLine().case(:else: breakelse).strip())

Of course, this syntax is pretty ugly, so let's just steal the `?` from the dynamic languages, overloading it
to represent `.case(:else: breakelse)`:

.. code-block:: D

    if (string line = eatLine()?.strip())

Huh! Suddenly it became very simple.

Note that while this *looks* like conditional access, it's actually a completely different operation.
The conditional access operator, written out, works like this:

.. code-block::

    op -- ?.op2 -- ?.op3

Ie. `?.member` is one operation.

Whereas `breakelse` works like this:

.. code-block::

    op -- ? -- .op2 -- ? -- .op3 -- ?

That is, `?` is a separate operation, and the member access just sees the plain type.

.. xe-quote:: shoebill

    So are you looking for idiomatic high-level code to have spelled-out `breakelse`'s or mostly just do
    things with a `?`, with `breakelse` being an implied lower-level mechanism for the `?`?

Honestly? I don't know.

----

See, the cool and also scary thing about being a compiler writer is that I can no longer be stopped.
This feature took about 130 lines of code in the Neat compiler. Now it's in a release and you can use it!
There are literally no checks on my power!

Is this a good idea? Honestly, I went into it expecting to hate it.
It's a bit "too slick", you know? And I am very sure that I will regret the keywords I
decided on. Also, I'd already overloaded `?` to automatically return error types, so it's
becoming a bit magical.

But after poking around with it for a bit, I think it may conceivably, possibly, be a good idea.
In concept.

You'll just have to
`download the compiler <https://github.com/Neat-Lang/neat/releases>`_ and try it out!
Let's find out if it's any good together.

.. [#] Out-pointers are a declaration of surrender for language designers.
    You already have a way to return data! It's the return value!
