+++
date = '2026-08-17T00:22:17+02:00'
draft = false
title = 'What is happening with Go ?'
toc = true
isStarred= true
categories = ['Reverse Engineering']
+++

## Introduction

In fact nothing special is happening with Go, I just wanted to get your attention but I swear you won't waste your time. Today we will talk about reverse engineering and we will dig into the guts of Go binaries. Be ready ! 

For context, Go is a high level language designed by Google in 2007. In the beginning the goal was to have something easier than C++ and something that compiles quickly.

What makes Go special is that every program embeds its own Runtime. This runtime is a set of functions that handles the memory allocations made in the program,the garbage collector, the scheduling of routine and so on.

As a result with a simple **printf("hello world")** we end up with a program containing a lot of functions. Add to that the stripping of the binary's symbols and analyzing a Go program can very quickly become extremely time consuming

![](/blog/go_sym/C.png)
Moreover it became very popular among malware developers because you write a Go program once and you can use it on Linux, Windows, phones etc. 

However solutions exist. Every Go program hosts what we call the pclntab and it contains all the information about the functions present in the program. 

And even in a basic stripped binary the memory map still shows us the start address of the pclntab.

![](/blog/go_sym/pcnltab.png)

### Our objectif  

At the end of this article, we should be able to recover all the function names for the stripped Go binary you saw on the screen above. We will focus on the new versions of Go, but once you do it for one version, you can easily generalize it to the others.
## Let's dig into the doc 

It's pretty hard to find online resources that clearly explain how to parse this table. And its structure changes from one Go version to another. 

The documentation for the official parser of the table, written in Go, is here: [https://go.dev/src/debug/gosym/pclntab.go](https://go.dev/src/debug/gosym/pclntab.go) 

We quickly understand that the Go version is determined by this structure:

```go
leMagic := abi.PCLnTabMagic(binary.LittleEndian.Uint32(t.Data))
	beMagic := abi.PCLnTabMagic(binary.BigEndian.Uint32(t.Data))

	switch {
	case leMagic == abi.Go12PCLnTabMagic:
		t.binary, possibleVersion = binary.LittleEndian, ver12
	case beMagic == abi.Go12PCLnTabMagic:

```

If we go to the top of the file, we find:

```go
import (
	"bytes"
	"encoding/binary"
	"internal/abi"
	"sort"
	"sync"
)
```

Which takes us here: [https://go.dev/src/internal/abi/symtab.go](https://go.dev/src/internal/abi/symtab.go)

```go
// PCLnTabMagic is the version at the start of the PC/line table.
// This is the start of the .pclntab section, and is also runtime.pcHeader.
// The magic numbers are chosen such that reading the value with
// a different endianness does not result in the same value.
// That lets us the magic number to determine the endianness.
type PCLnTabMagic uint32

const (
	// Initial PCLnTabMagic value used in Go 1.2 through Go 1.15.
	Go12PCLnTabMagic PCLnTabMagic = 0xfffffffb
	// PCLnTabMagic value used in Go 1.16 through Go 1.17.
	// Several fields added to header (CL 241598).
	Go116PCLnTabMagic PCLnTabMagic = 0xfffffffa
	// PCLnTabMagic value used in Go 1.18 through Go 1.19.
	// Entry PC of func data changed from address to offset (CL 351463).
	Go118PCLnTabMagic PCLnTabMagic = 0xfffffff0
	// PCLnTabMagic value used in Go 1.20 and later.
	// A ":" was added to generated symbol names (#37762).
	Go120PCLnTabMagic PCLnTabMagic = 0xfffffff1
)
```

We can now link a magic byte to its version.
The header of our binary's pclntab begins with "FF FF FF F1". It's the 1.20 version of Go.

![](/blog/go_sym/magics.png)

Here is how the header is organized:

```go
// Check header: 4-byte magic, two zeros, pc quantum, pointer size.
	if len(t.Data) < 16 || t.Data[4] != 0 || t.Data[5] != 0 ||
		(t.Data[6] != 1 && t.Data[6] != 2 && t.Data[6] != 4) || // pc quantum
		(t.Data[7] != 4 && t.Data[7] != 8) { // pointer size
		return
	}
```

- The 4 first bytes are the magic byte as saw above.
- The byte 5 and 6 are equals to zero.
- The 7th byte is the "pc quantum" (I don't really know what that is)
- The 8th one tells us about the size of a pointer.

Further down in the source code, we find this interesting function:

```go
func (t *LineTable) go12Funcs() []Func {
	// Assume it is malformed and return nil on error.
	if !disableRecover {
		defer func() {
			recover()
		}()
	}

	ft := t.funcTab()
	funcs := make([]Func, ft.Count())
	syms := make([]Sym, len(funcs))
	for i := range funcs {
		f := &funcs[i]
		f.Entry = ft.pc(i)
		f.End = ft.pc(i + 1)
		info := t.funcData(uint32(i))
		f.LineTable = t
		f.FrameSize = int(info.deferreturn())
		syms[i] = Sym{
			Value:     f.Entry,
			Type:      'T',
			Name:      t.funcName(info.nameOff()),
			GoType:    0,
			Func:      f,
			goVersion: t.version,
		}
		f.Sym = &syms[i]
	}
	return funcs
}
```

It takes an array called `funcTab()`. This looks like an array containing all the data about each function in the program.

And the part that interests us here is:

```go
f.Entry = ft.pc(i)
Value:     f.Entry,
[...]
Name:      t.funcName(info.nameOff()),
```

Everything we need is right here: a program counter (the address of the function in Ghidra) and the name associated with the function.

So we just need to understand how this function works, where it is called, and how to find the different structures in the binary. This will allow us to parse the pclntab later! (I hope ^^)
### Let's find the addresses 

PC = Program Counter, the address of the next instruction the CPU should run. We now have to understand how to parse a field in this `funcTab` array.

For the `f.Entry` variable that contains the function's address, we should look at the `pc` method of the `funcTab` object:

```go
// pc returns the PC of the i'th func in f.
func (f funcTab) pc(i int) uint64 {
	u := f.uint(f.functab[2*i*f.sz:])
	if f.version >= ver118 {
		u += f.textStart
	}
	return u
}
```

We understand here that from `functab`, by jumping `(2 * i * f.sz) + textStart` bytes (where `i` is our counter), we should get all the PCs!

Let's clarify what `f.sz` and `textStart` are. `f.sz` refers to:

```go
sz int // cached result of t.functabFieldSize
```

```go
// functabFieldSize returns the size in bytes of a single functab field.
func (t *LineTable) functabFieldSize() int {
	if t.version >= ver118 {
		return 4
	}
	return int(t.ptrsize)
}
```

Ok so f.sz = 4 for in our case.
For textStart it explained : 

```go
textStart   uint64 // address of runtime.text symbol (1.18+)
```

Okay, so `f.sz = 4` in our case.
For `textStart`, it is explained like this: 

```go
textStart uint64 // address of runtime.text symbol (1.18+)
```

Now, let's find where `functab` starts in our binary.
### Gotta catch functab!

In the same file, the `parsePclnTab()` function is present. It parses the different components of the pclntab and initializes a structure. 

Here is an extract of the function:

```go
case ver118, ver120:
		t.nfunctab = uint32(offset(0))
		t.nfiletab = uint32(offset(1))
		t.textStart = t.PC // use the start PC instead of reading from the table, which may be unrelocated
		t.funcnametab = data(3)
		t.cutab = data(4)
		t.filetab = data(5)
		t.pctab = data(6)
		t.funcdata = data(7)
		t.functab = data(7)
		functabsize := (int(t.nfunctab)*2 + 1) * t.functabFieldSize()
		t.functab = t.functab[:functabsize]
	case ver116:
		t.nfunctab = uint32(offset(0))
		t.nfiletab = uint32(offset(1))
```

First, we see that the parsing method changes depending on the Go version. Anyway, we are looking for `functab`!

```go 
t.functab = data(7)
```

```go
offset := func(word uint32) uint64 {
		return t.uintptr(t.Data[8+word*t.ptrsize:])
	}
	data := func(word uint32) []byte {
		return t.Data[offset(word):]
	}
```

Now we know that `functab` starts at this offset:

```go
t.Data[8 + 7 * 4]
```

(t.Data[0] represents the start of the pclntab in the binary).
And to jump from one PC to the next, according to the `pc` function we saw earlier, we have to calculate the addresses like this:

```go
(t.Data[8+7*4])[2 * PC_NUM * 4]
```

We are now able to get all the PCs. Next, we have to associate each PC with its function name.
### What about the names?

As a reminder:

```go
info := t.funcData(uint32(i))
[...]
Name:      t.funcName(info.nameOff()),
```

First, we need to know how to get `t.funcData(i)`. In other words, how to get the `funcData` associated with a PC. `funcData` is a method name that also return an funcData object type :

```go 
func (t *LineTable) funcData(i uint32) funcData {
	data := t.funcdata[t.funcTab().funcOff(int(i)):]
	return funcData{t: t, data: data}
}
```

Let's see what `funcOff` is:

```go
func (f funcTab) funcOff(i int) uint64 {
	return f.uint(f.functab[(2*i+1)*f.sz:])
}
```

We notice that you can find a PC at `2 * i * sz + textStart` and data at `(2 * i + 1) * sz`.
Now we only have a pointer to the function's metadata, but still not its name. Let's dig a little deeper.

Here is the `nameOff` method:

```go
func (f funcData) nameOff() uint32     { return f.field(1) }
```

Which takes us to the `field` method :

```go
func (f funcData) field(n uint32) uint32 {
	if n == 0 || n > 9 {
		panic("bad funcdata field")
	}
	// In Go 1.18, the first field of _func changed
	// from a uintptr entry PC to a uint32 entry offset.
	sz0 := f.t.ptrsize
	if f.t.version >= ver118 {
		sz0 = 4
	}
	off := sz0 + (n-1)*4 // subsequent fields are 4 bytes each
	data := f.data[off:]
	return f.t.binary.Uint32(data)
}
```

So : 

```go
info.nameOff() = info.field(1) = info.t.binary.Uint32(4)
```

For `info = funcData(i)`, I have to read 4 bytes after its start address. (each function has its funcData).

Right now we only have an offset. Fortunately, there is also a method to find the string address from this offset :

```go
// funcName returns the name of the function found at off.
func (t *LineTable) funcName(off uint32) string {
	if s, ok := t.funcNames[off]; ok {
		return s
	}
	i := bytes.IndexByte(t.funcnametab[off:], 0)
	s := string(t.funcnametab[off : off+uint32(i)])
	t.funcNames[off] = s
	return s
}
```

This function takes the `funcnametab` and returns all the bytes between `funcnametab` + offset and the first null byte.

We just need to find the `functabsize` so we know when to stop our loop. In the `parsePclnTab` function, we notice this line :

```go
functabsize := (int(t.nfunctab)*2 + 1) * t.functabFieldSize()
```

```go
t.nfunctab = uint32(offset(0))
```

```go
func (t *LineTable) functabFieldSize() int {
	if t.version >= ver118 {
		return 4
	}
	return int(t.ptrsize)
}
```

As a reminder, `offset(0)` corresponds to `t.Data[8]`, which is the 8th byte of the pclntab. And `t.Data[0]` points to the start of the pclntab. (See the `offset` function earlier in the article).

So :

```go
functabsize = (t.Data[8] * 2 + 1)  * 4
```

Here is a schema that summarizes evrything :
(The cyan are for offset / addresses)
(Green for our objectif PC and Name)
(Dark Blue for component of pclntab)

![](/blog/go_sym/schema2.svg)


Now we got all the theorical knowledge to parse the table, let's CODE ! 
## A little Jhydra introduction 

(Jhydra means nothing, I just like how the word sounds ;). 

But more seriously, the Ghidra Flat API is extremely well documented. For every task our algorithm needs to perform, you will find a built-in method ready to handle it.

We will be using Jython, which is essentially a mix between Java and Python. It is commonly used to write Ghidra scripts to automate tasks like creating labels at specific addresses, manipulating program memory, analyzing instructions, and much more.

Here is the documentation for all the functions we will need:[https://ghidra.re/ghidra_docs/api/ghidra/program/flatapi/FlatProgramAPI.html](https://ghidra.re/ghidra_docs/api/ghidra/program/flatapi/FlatProgramAPI.html)

Let's begin by writing the algorithm. We will take the schema below as a reference to map out our logic :

```go
START = getAddress(pcnltab)
TEXT_START = getAddress(text_segment)

PTRSIZE = getPtrSize()

FUNCNAMETAB_OFFSET = getValueFromAddress(START + 8 + (3 * PTRSIZE))
FUNCNAMETAB = START + FUNCNAMETAB_OFFSET

FUNCTAB_OFFSET = getValueFromAddress(START + 8 + (7 * PTRSIZE))
FUNCTAB = START + FUNCTAB_OFFSET

NFUNCTAB = getValueFromAddress(START + 8)

i = 0 

WHILE i < NFUNCTAB DO : 
	ENTRY_ADDR = FUNCTAB + (i * 8)
	PC_OFFSET = getValueFromAddress(ENTRY_ADDR)
	PC = TEXT_START + PC_OFFSET 
	FUNCDATA_OFFSET = getValueFromAddress(ENTRY_ADDR + 4)
	FUNCDATA_ADDR = FUNCTAB + FUNCDATA_OFFSET
	NAME_OFFSET = getValueFromAddress(FUNCDATA_ADDR + 4)
	FUNCNAME = getString(FUNCNAMETAB + NAME_OFFSET)
	AddSymbolToAddress(PC, FUNCNAME)
	i = i + 1
```

### Some useful functions 

Now we just have to find the associated functions in the documentation. For example, if you want to get the start address of the `gopclntab` (if the section is still in the binary) :

```python
START = getMemoryBlock(".gopclntab").getStart()
```

If you want to get the data at a specific address:

```python 
FUNCNAMETAB_OFFSET = getInt(START.add(0x08 + (3 * PTRSIZE)))
```

And if you want to set a label over a specific address:

```python
createLabel(pc, func_name, True)
```

After the first execution, a small problem remained. Strangely, some functions had long names with special characters, so I just replaced them with underscores.

![](https://shennmue.github.io/blog/go_sym/ghidra_error.png)

I fixed this by adding this loop just before creating the label:

```python
func_name = func_string
special_chr = [' ', '*', '(', ')', '[', ']', '{', '}', ',', '<', '>',' ']
for char in special_chr:
func_name = func_name.replace(i, '_')
```

There we go we finally done !!

![](https://shennmue.github.io/blog/go_sym/result.png)


## To conclude 

Here is the link of the script : [Go Symbol Restoration Project ](https://github.com/shennmue/ghidra-go-symbol-restore/tree/main)

I really enjoyed digging into the Go runtime's guts. Understanding how this pclntab works step by step was like solving a big puzzle, and I had a lot of fun doing it.
I am very excited to explore other RE topics and share them with you in the future. Maybe we will analyze a Go malware, or discover symbolic execution?

See you soon for a new journey :)

Ali Hammoudi.
