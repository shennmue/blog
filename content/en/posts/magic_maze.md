+++
date = '2026-08-16T20:34:53+02:00'
draft = false
title = 'Magic Maze'
categories = ['CTF']
+++

# Context 

A Pwn (Binary Exploitation) challenge focused on a Format String vulnerability.
Made for Jeanne d'Hack CTF, capture the flag which take place in Rouen.

The sources for the challenge are here : https://github.com/shennmue/ctf_challenges/tree/main/pwn/Magic%20Maze

## The Pitch

> A developer friend of yours found a box containing the first video games he ever coded, and among them was Magic Maze.
> The name caught your attention, and you decided to try it out when you got home...

## Objective

The goal of this challenge is to analyze and exploit the provided binary by leveraging a format string vulnerability to leak memory, predict the correct path, and obtain the flag.

## Write Up

The goal of the challenge was to exploit a Format String vulnerability. This occurs when a call to the printf function is made without using a format string, passing user input directly as an argument instead. If the user injects format specifiers (like %x, %s, or %n)  they can arbitrarily read or write to the program's memory
In the main function, we notice a call to handle_direction :

![Heap Overflow](https://shennmue.github.io/blog/maze/handle.png "Heap Overflow") 

At the beginning of this function, an array is defined containing all possible movements :

![Heap Overflow](https://shennmue.github.io/blog/maze/direction.png "Heap Overflow") 

When a user inputs something other than one of the four directional arrows, their input is displayed as is :

![Heap Overflow](https://shennmue.github.io/blog/maze/string.png "Heap Overflow") 

This is where the vulnerability lies. mvwprintw works like printf; by displaying user input without a format string, we can read the program's memory. Furthermore, during the first attempt, the chosen direction i is stored in a variable via the call to random_choice :

![Heap Overflow](https://shennmue.github.io/blog/maze/random_choice.png "Heap Overflow") 

![Heap Overflow](https://shennmue.github.io/blog/maze/random_choice_func.png "Heap Overflow") 

At each iteration, the return value of random_choice ends up on the stack. If we leak the memory, we can recover each position from the first phase by using an input like
```%p.%p.%p.%p.%p.%p.%p.%p.%p.%p```, we then get the following output:

![Heap Overflow](https://shennmue.github.io/blog/maze/res.png "Heap Overflow") 

Finally thanks to the array defined earlier we can deduce the correct movements to use during the second chance given by the mage, and we obtain the flag.

![Heap Overflow](https://shennmue.github.io/blog/maze/flag.png "Heap Overflow") 

### Annexe 

This year, the theme of the CTF was video games. I tried to make this challenge look like a video game using `ncurses`. It was my first time using this library, which is why I particularly loved making this challenge ! 

Here are some other pics :

![Heap Overflow](https://shennmue.github.io/blog/maze/intro.png "Heap Overflow") 
![Heap Overflow](https://shennmue.github.io/blog/maze/first_part.png "Heap Overflow") 
![Heap Overflow](https://shennmue.github.io/blog/maze/second_part.png "Heap Overflow") 
![Heap Overflow](https://shennmue.github.io/blog/maze/end.png "Heap Overflow") 

