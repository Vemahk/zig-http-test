# Zig HTTP Server

Made with [zig](https://ziglang.org/),
[zap](https://github.com/zigzap/zap),
[mustache-zig](https://github.com/batiati/mustache-zig),
[htmx](https://htmx.org/),
and [tailwind](https://tailwindcss.com/).

## Purpose

I work mainly in web dev, and I like zig.  Thought I'd see how the two went together.

## Findings

Yeah.  It's pretty aight.

Kinda wish zig had some kind of interface/trait system, but I get by.

I've had to do a lot of legwork to very little website running.  I'm hoping with all the work I've put into the backend that I'll get to spend more time developing the website itself, but I have yet to put a whole lot into it.

I really enjoy the level of control C and Zig grant, but I've never liked working in C.  Too many quirks with the language, arrays are just pointers and don't preserve length, it's hard to do it right.  Zig seems fairly straightforward to do both well and correctly, and it's been surprizingly easy to learn (granted, after many years programming experience behind it).

So far, it's been a very positive experience.

# Bugs?

## In Zig

I've noticed that if an error occurs behind a duck type (`anytype`), the stack trace is sometimes destroyed, and it's not possible to tell where an error is occuring.  Judging Zig for that it does not have interfaces and relies heavily on duck-typing for polymorphism, this is a huge pain point for working with Zig.

I've also tried and failed to use the built in http client to pull requests from https.  The error was very strange and I wasn't able to work through it with the limited amount of time I allocated to it.

## In Zap

None, really.  Very smooth.

## In Mustache-Zig

Haven't had much a chance to mess around with it.

## In HTMX

Haven't had much a chance to mess around with it :(.

## In my own code

Ha, there are plenty.

I'm keeping a decent track of feature I want and bugs I notice in the Issues tab.  Check those out if you're curious.  Since this is a personal project, I'm not terribly inclined to tag things, though...
