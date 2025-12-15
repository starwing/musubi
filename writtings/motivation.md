# Building Musubi: Hand-Porting Rust's Ariadne to C (A Story of Manual Coding with LLM Assistance)

> A month-long journey of manually porting a complex diagnostic renderer from Rust to C, where I learned what LLMs can and cannot do.

## Initial Motivation and Selection

Finding or building a good-looking and functional diagnostic rendering library has always been on my mind - after all, Lua's stack trace display can only be described as rudimentary. Recently, I've been considering implementing an algebraic effects language with Rust-like syntax that compiles to C. This seemed like a good time to research what diagnostic libraries are available. I planned to start with a Lua compiler prototype, since Rust requires you to have everything figured out from the start, and Go feels a bit heavy. While I love pure C, starting a prototype directly in C seemed too extreme. However, if there's a Rust implementation, creating Lua bindings for it would be straightforward.

I was initially attracted to [ariadne](https://github.com/zesterer/ariadne), which looked great. However, I desperately wanted a "width limiting" feature - this was my main motivation for wanting to implement a good diagnostic library: when code lines are too long (usually in generated code), I wanted the diagnostic library to effectively extract and display the most relevant fragments within a limited width. During my search, I found the [codesnake](https://github.com/01mf02/codesnake) library, which looked almost as good and was apparently some kind of rewrite of ariadne. The author commented on several other libraries and described that his main reason for writing his own was that ariadne had broken semver and broken his code. I tried codesnake but immediately hit a wall - it doesn't support overlapping labels.

At that time, I didn't know about [annotate-snippets](https://github.com/rust-lang/annotate-snippets-rs), which was rather silly - after all, what initially attracted me to search for a suitable library in Rust was because rustc's diagnostic messages are beautiful and have a "soft limit of 140 characters." Actually, I only noticed annotate-snippets after implementing musubi. It's rustc's official diagnostic library. Initially, I found annotate-snippets' interface a bit obscure, but it's actually fine once you get used to it. Moreover, annotate-snippets' "diff mode" looks very useful, and it supports other elements after help/note, making it relatively flexible. Its only "issue" might be that placing message text directly after labels makes things a bit long. But it's actually fine. However, its interface really can't be easily implemented - it's basically a library that completely depends on Rust's expressiveness, with no way to implement a flexible and nice-looking interface in C.

Anyway, since ariadne doesn't support width limiting, codesnake doesn't support overlapping labels, and online comments seemed to have issues with [miette](https://github.com/zkat/miette) (like being derive-based, not as flexible as ariadne), plus ariadne's giant render function looked really unreliable ([its own comments](https://github.com/zesterer/ariadne/blob/4b3807ca8872190aec080e1825b6852b7d2b68ba/src/write.rs#L9) mention that this thing is hard to understand and modify), I decided to implement an ariadne clone myself. On one hand, to learn how such complex diagnostic output is calculated; on the other hand, porting to C would allow me to create Lua bindings. Plus, I could practice binding pure C code in Rust (supposedly very simple, I wanted to try), and practice LLM vibe coding (turns out, this is currently an immature field...). And so I began.

## Lua Prototype Development

Initially, I thought it would be simple. I directly told Copilot "I have a Rust project, please translate it one-to-one to Lua," thinking I'd get corresponding Lua code first, then slowly modify it. Turns out this was a disaster. I used up all my Copilot Pro token quota, and the generated code still couldn't be used. I found that it actually ignored a lot of logic, then used various makeshift ways to barely pass unit tests. "This won't work," I thought. After two weeks, I deleted all the LLM-generated code and decided to do it myself.

Translating ariadne to Lua went quite smoothly. I basically [completed this work in several days](https://github.com/starwing/musubi/blob/4b90e6b89efea36e64035b40ab0a3fd181efca44/ariadne.lua), including refactoring from OOP style to C style to facilitate the subsequent C port. Actually, I found that LLM's biggest advantage is reviewing my code - it can find some low-level errors, but that's about it. Even when it says code quality is good, debugging is still needed to solve problems it didn't find. Anyway, I eventually translated ariadne to Lua and successfully ran most of ariadne's own unit tests - though ariadne itself doesn't have that many unit tests.

Then I started optimizing the code on this foundation. First, I eliminated all lambdas and replaced them with external functions, breaking it down into something C could handle. Then some complex parts - like [`write_margin`](https://github.com/zesterer/ariadne/blob/4b3807ca8872190aec080e1825b6852b7d2b68ba/src/write.rs#L337) - were decomposed into multiple functions ([`render_lineno`](https://github.com/starwing/musubi/blob/4b90e6b89efea36e64035b40ab0a3fd181efca44/ariadne.lua#L1392), [`render_margin`](https://github.com/starwing/musubi/blob/4b90e6b89efea36e64035b40ab0a3fd181efca44/ariadne.lua#L1189), etc.). At this point, I discovered some bugs in ariadne itself, as well as unreliable implementation aspects. The most obvious was that giant `write_margin` using a nested loop. Let me explain ariadne's naming for rendered output, using this example:

```text
[3] Error: Incompatible types
   ,-[ sample.tao:1:12 ]
   |
 1 | ,-----> def five = match () in {
   | |                  ^
   | | ,----------------'
 2 | | |         () => 5,
   | | |               |
   | | |               `-- This is of type Nat
 3 | | |         () => "5",
   | | |               ^|^
   | | |                `--- This is of type Str
 4 | | |---> }
   | | |     ^
   | | `--------- This values are outputs of this match expression
   | |       |
   | `-------^--- The definition has a problem
   |
 6 |     ,-> def six =
   :     :
 8 |     |->     + 1
   |     |
   |     `------------- Usage of definition here
   |
   | Note: Outputs of match expressions must coerce to the same type
---'
```

The top `[3] Error: ...` is called the header, the bottom note to the end is called the footer, and the middle part is grouped into different groups based on code files. The margin is where those vertical lines and horizontal arrows on the left side of each code line are located. As you can see, this position is drawn with "two character widths for each multi-line label", and `write_margin` does this.

`write_margin`'s outer loop runs from 0 to len+1 to calculate what information should be displayed in the current two characters (one character in `compact` mode), while the inner loop runs again from 0 to the current position to determine things like "is this block a horizontal bar (hbar), vertical bar (vbar), or pointer (ptr)?" I realized there's no need to traverse from 0 to the current position every time you output two characters to find these elements. Actually, for boundaries, as long as there's an hbar or ptr ahead, it means you basically don't need to look further - these elements will definitely continue. So these two values just need to be maintained during the loop, while corners (the `,` and `` ` `` characters on the left in the example above) and vertical bars need to be checked each time. Thus, a nested loop was optimized into a single loop + conditional checks, greatly simplifying the code. Additionally, the ptr head (`->`) can only appear at the end, so there's no need to loop len + 1 times - just loop len times, then check afterwards whether to append an arrow, horizontal bar, or space. The code became simpler.

This optimization of the original code gave me confidence. Subsequent code refactoring went smoothly. Just like that, optimizing code while testing, the initial version was quickly completed. Then I implemented the width limiting feature with LLM's help. Basically, I'd list requirements, it would list approaches, then I'd choose one that looked reliable and write the code myself, then it would review. I found this way of using LLMs is actually the best. Then I had it write unit tests, but ignore the results - I'd run the tests myself and see if the (definitely failing) results were reasonable. If reasonable, I'd directly paste the results into the tests. And so the Lua code was completed. I fixed many display issues, deleted some unreachable logic, achieved coverage, and covered some branches that even ariadne itself hadn't covered with unit tests. At this point, the LLM also thought we could consider porting to C. So I started.

## C Implementation

The C port went quickly. Actually, LLMs should be able to do this kind of work well, but I was already scared off. After three days, the C port was done. I added Lua bindings and ran all the previous test cases. Compared to the Lua code, the most troublesome part was Unicode handling - after all, there's no [luautf8](https://github.com/starwing/luautf8) in C - fortunately, I wrote that library too. I trimmed the functionality I needed to the C side and made targeted optimizations - an important optimization was adding a width cache, which effectively reduced the need to "repeatedly calculate code width" in C. You can just binary search in the width cache. And because of the width cache, I could implement the [UAX#29](https://www.unicode.org/reports/tr29/) algorithm (only the parts I needed, like Emoji and country flags - I didn't bother with things like Hangul syllables) that even the Lua version didn't have. And surprisingly, this fixed a bug in ariadne that I hadn't even noticed - ariadne calculates tab stops using `col` (i.e. the character index in line)! But `col` isn't necessarily width 1. You actually need to use "accumulated width from the start" rather than `col`. This means if a line of code has two tabs, the calculation for the second tab is wrong.

Anyway, after confirming the code basically had no major issues (coverage reached 100%), I released musubi version 0.1.0. The Rust bindings for this version were basically written by LLM, but no big deal - after all, the core C code was written by me... right?

Turns out you really can't trust LLM-written code... The binding quality was terrible - it even missed binding an entire class... So I had to release version 0.2.0, re-reviewed all the code, fixed some binding issues, added the `ColorGenerator` binding the LLM forgot, and some documentation it forgot. Finally, I added Github Actions to ensure Lua bindings work on all Lua versions (this took me some time).

## New Improvements (Versions 0.3.0 and 0.4.0)

But obviously, I couldn't relax yet. After release, I played around with it a bit. While ariadne-style diagnostics are indeed beautiful, there were too many line crossings... Around this time, I discovered the annotate-snippets library, which basically has no line crossings (though I wonder if it can support complex overlapping labels...). Anyway, one solution to line crossings is "draw the rightmost label first, then the left ones." For example, this is annotate-snippets' output:

```text
error: expected type, found `22`
   ╭▸ examples/footer.rs:29:25
   │
26 │                 annotations: vec![SourceAnnotation {
   │                 ┬──────────  ┬──  ──────────────── while parsing this struct
   │                 │            │
   │                 │            This type
   │                 This is the key
   ‡
29 │                 range: <22, 25>,
   ╰╴                        ━━ expected struct `annotate_snippets::snippet::Slice`, found reference
```

And this is ariadne's:

```text
Error: expected type, found `22`
   ╭─[ examples/footer.rs:1:27 ]
   │
 1 │                 annotations: vec![SourceAnnotation {
   │                 ─────┬─────  ─┬─  ────────┬───────
   │                      ╰────────────────────────────── This is the key
   │                               │           │
   │                               ╰───────────────────── This type
   │                                           │
   │                                           ╰───────── while parsing this struct
   │
   │
 4 │                 range: <22, 25>,
   │                         ─┬
   │                          ╰── expected struct `annotate_snippets::snippet::Slice`, found reference
───╯
```

As you can see, line crossing is directly caused by ordering issues. So I fixed this - just carefully tuning the label order. I also improved margin label selection - one main reason I like ariadne is that it can select a label and put its arrow in the front margin column to simplify label lines. This time I carefully selected the most appropriate labels, so that [even such complex labels](https://github.com/starwing/musubi/blob/be3c499b5440b329b7b3071c980b7a99578a446d/tests/test.lua#L1041) look much better in `compact` mode:

```text
Error: natural label order
   ,-[ <unknown>:1:1 ]
 1 |  ,-->first line
   |,-|---'
   ||,|---'
 2 ||||-->second line
   ||||       ^|^|^|^
   ||||       |||||`|-- last inline
   ||||       |||`|-|-- middle inline
   ||||       |`|-|-|-- first inline
   |||`-------|-|-|-|-- margin
   ||`--------|-^-|-|-- first outer
   |`---------|---|-^-- last outer
   |   ,------'   |
   |   |,---------'
 3 |   ||>third line
   |   |`--|---------- first next
   |   `---^---------- second next
```

To be more like annotate-snippets' space-saving layout, I also added an option to "disable label message alignment." Then I released version 0.3.0.

I thought this was basically done and I could peacefully return to writing my algebraic effects generator. But playing around with it, I discovered a major problem: I store source code through the `mu_Source` structure, but its lifecycle is bound to `mu_Report`! This means if I want to display labels for a source code multiple times, I have to initialize these source codes over and over, calculating their line number positions! This was terrible. I decided to follow ariadne's lead and re-introduce the `mu_Cache` structure (I had previously merged it into `mu_Report`, which proved to be a bad idea). `mu_Cache`, like `mu_Report`, supports custom memory management and internally maintains `mu_Source`'s lifecycle. And since `mu_Source` itself embeds a `mu_Cache`, it can be directly passed to `mu_render`. Very comfortable. But the Rust bindings were in trouble. This is basically C trickery - how to bind it... The LLM was basically clueless. I had to do it myself. After an evening of trying various methods, I finally solved the main lifecycle problem by "storing Rust objects in C-allocated memory," plus various interface trade-offs. I released version 0.4.0. This version is relatively comfortable to use now.

## New Features (Version 0.5.0)

Was this the end...? No... A shocking piece of news... While I was busy updating the code, I didn't notice that ariadne, which hadn't updated in 4 months, suddenly had an explosive update! I was shocked - I finished writing everything and only then you update? And it fixed some issues I had found earlier (like the margin hbar update issue) and added cross-minimization functionality... Alright... But it still didn't implement width limiting, which I wanted most, and some bugs still aren't fixed - like the tab calculation issue. Anyway, it made many changes. Some I thought were good - like prioritizing vertical bars over horizontal bars when crossing. This is indeed clearer. But some changes I didn't like - like changing underlines in ASCII mode from "`^^^`" to "`---`". Lost the flavor. Anyway, I added some features from ariadne's updates that I liked, including:

- `line_margin` markers - now the left edge marker for "current line is code line" can be customized.
- Left, middle, and right `underbar` - I also added a "zero-width" `underbar`, so if a label has no width, it can display an arrow-like underline to indicate this.
- Cross-file `order` option. Alright, sounds reasonable.
- `context_lines` to display additional context length. Not bad, this feature sounds quite useful.

Anyway, with the new features, I also greatly simplified the previous `mu_Group` creation process. The code looks better :D  I also removed the "can additionally specify position" attribute - don't really need it anyway. After all, randomly specifying a position that doesn't even have a label feels weird... But to let users specify "use this label's position to display this code block's marker," I added `primary` functionality. Now you can specify a label as primary, and its position will be displayed at the beginning of the current code group (the position in brackets in the example above). Anyway, the logic is clearer and the code is simpler. Very good. Now the C code basically consists of functions within 40 lines (a few functions have 50+ lines, really can't optimize them further...). The code implementation is clean and tidy, making it much easier to add new features.

In the end, I didn't expect such a simple feature to take me a month. If I hadn't used LLMs from the start, it might have been faster... Research shows LLMs reduce programmer efficiency, and now I really believe it... But LLMs still have benefits. For things you can't figure out or don't want to think about, you can ask directly and get ideas. Use it as a cyber rubber duck. Have it review after writing code. Plus Copilot's code suggestion feature is indeed quite useful. So there are still advantages. How to put it - trading "reduced development efficiency" for "programmers daring to implement features they previously lacked confidence in" - I think it's worth it.

So this is this month's development log. Developing musubi was quite interesting. The process of slowly unwrapping ariadne's long and complex spaghetti code and turning it into C code was fun. Being able to generate beautiful diagnostic information with my own library is very fulfilling. I can go back to continuing my algebraic effects research.

## Future Plans

Musubi is now a fully-featured, high-performance diagnostic library. The next work focus will shift to:

1. Actually using it in my algebraic effects compiler to accumulate more practical experience
2. Continuing to track ariadne updates and absorb valuable improvements
3. Possibly considering implementing annotate-snippets' diff mode
4. Improving documentation and use cases

If you're looking for a lightweight, high-performance diagnostic library with width limiting support, feel free to try [musubi](https://github.com/starwing/musubi)!
