+++
date = '2026-08-16T20:12:45+02:00'
draft = false
title = 'Draconophobia'
categories = ['CTF']
+++

A Pwn (Binary Exploitation) challenge focused on heap corruption. Made for Jeanne d’Hack CTF, capture the flag which take place in Rouen.

The sources for the challenge are here : https://github.com/shennmue/ctf_challenges/tree/main/pwn/draconophobia

## The Pitch

> You and your friend have been sent on a mission to defeat the mountain dragon. 
> This quest will reward you with experience points and fame. 
> Do you accept it?

## Objective

The goal of this challenge is to analyze and exploit the provided binary to successfully trigger the `lvl_up` function and read the contents of the `flag.txt` file.

## Write Up

By observing the main function, we notice two variables that resemble structures. Using Ghidra's automatic structure generation tool, we get:

![Heap Overflow](https://shennmue.github.io/blog/draco/struct.png "Heap Overflow")

This field initially has a size of 8 as indicated by the malloc, but no size check is performed, which introduces a heap overflow.

![Heap Overflow](https://shennmue.github.io/blog/draco/scanf.png "Heap Overflow")

To obtain the flag, it is necessary to successfully execute the ```lvl_up``` function.

The first step is to calculate the number of bytes required to write into the second structure from the scanf that is supposed to write only into the ```pseudo``` field of the first structure.

To do this, we can run the program with a debugger, place a breakpoint before the end of the program, provide two arguments, and then observe in memory where ```search arg..``` is located in order to calculate the exact offset.

In a second step, we observe that ```PIE``` is not enabled. The addresses of the different functions are therefore not randomized.
The idea is then to make a field of the second structure point to the ```GOT``` address of the strcmp function, which will be executed later.

Output of command ```objdump -R draconophobia``` : 

![Heap Overflow](https://shennmue.github.io/blog/draco/got.png "Heap Overflow")

Output of command ```objdump -D draconophobia | grep lvl_up``` : 

![Heap Overflow](https://shennmue.github.io/blog/draco/lvl_up.png "Heap Overflow")

Next, we provide, as the second argument, the address of the `lvl_up` function, which will be written in place of the `strcmp` address in the GOT. 
During the next call to `strcmp`, the `lvl_up` function will be executed instead.

Then you got this exploit : 

![Heap Overflow](https://shennmue.github.io/blog/draco/payload.png "Heap Overflow")

This way, we obtain the flag `JDHACK{41du1n_WIlL_N3ver_w!n}`.


![Heap Overflow](https://shennmue.github.io/blog/draco/draco.gif "Heap Overflow")

