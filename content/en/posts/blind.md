+++
date = '2026-08-15T22:12:13+02:00'
draft = false
title = 'MP4 "obfuscation"'
categories = ['CTF']
+++

# Context

A steganography challenge using an MP4 file to hide data, created for the **Jeanne d'Hack CTF**, a capture-the-flag competition that takes place in Rouen.

The sources and solve script for the challenge are available [here](https://github.com/shennmue/ctf_challenges/tree/main/steganography/blind_distribution).

## The Pitch

>Your nephew was thrilled to have recorded his very first video of his favorite game. >Unfortunately, he spilled coffee all over his laptop, and now his video isn’t loading >correctly anymore… Help him recover the original footage!

## Objective

The screen is dark ! Find why and get back the original video. 

![](https://shennmue.github.io/blog/blind/blind.png)


## MP4 file’s structure

MP4 files are organized into boxes. Each box contains other boxes, which together form the file’s ecosystem. Each one has a different purpose, a specific size, and a precise type.

An important example of a box is `mdat`: this one contains all the raw data related to the file’s audio and images.

A box header is always at least 8 bytes long:
* The first 4 bytes define the total Size of the box.
* The next 4 bytes define the Type (its name in 4 ASCII characters).

Therefore, to navigate through the tree structure, you simply need to read the size and the name of the box. If it interests us, we “enter” it by reading the following 8 bytes; otherwise, we move forward by the size of the entire box.

Here is the nesting of these boxes according to the ISO/IEC 14496-12 standard:

![](https://shennmue.github.io/blog/navy/norme.png)

Furthermore, generally all information related to the video is found in two `trak` atoms: one for audio data and one for video data.

When an MP4 file contains multiple tracks, almost all players offer an option to switch between the different tracks contained within the same file.

## Write Up

There are several reasons why an MP4 player might fail to display any image while still playing the audio track. In this case, we need to focus on the `stco` atom (Chunk Offset Box).

This is one of the most important atoms, as it indicates for each video chunk which offset within the `mdat` atom to go to in order to find the corresponding data.

A chunk is a set of one or more frames (an image). In an MP4 file, to prevent the player from constantly jumping back and forth between the audio and video tracks, the data is split into these small blocks called chunks. Therefore, you usually find a video chunk, followed by an audio chunk, and so on, interleaved within the `mdat` atom.

Thus, the `stco` atom contains a table that lists the exact location of each chunk:

```text
Chunk 1 -> Offset X
Chunk 2 -> Offset Y
…
```
Without these indexes, the player cannot know where the raw data starts and ends within the `mdat`, rendering the video unplayable.

When analyzing the `stco` box:

![](https://shennmue.github.io/blog/blind/shuffle_stco.png)

We notice that the offsets associated with the different chunks are out of order. However, in a standard MP4 file, these addresses within the `stco` atom must almost systematically appear in ascending order, as they follow the physical progression of the data in the `mdat` atom.

By simply sorting this list to put the addresses back into the correct numerical order, we realign the playback with the actual position of the data on the disk, allowing the original video to be recovered.

Congratulation you saved your nephew gameplay ! 

![](https://shennmue.github.io/blog/blind/result.png)
