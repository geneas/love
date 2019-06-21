# love
Odds'n'ends for Löve (love2d) projects


### id3.lua:

Module to read ID3 tags from mp3 files.
Contains a single function **load(fd, setpos)** -> *table* or -> *nil, errormsg*

*fd* must be some kind of file object which implements the method *read*(n) to read the next &lt;n> bytes from the file.
The file object must initially be positioned at the start of the file. 
The function returns a table containing the following fields (if found):

	CreatedBy [string]
	TrackName [string]
	Artist [string]
	Album [string]
	TrackNumber [number]
	Genre [string]
	Year [number]
	Length [in seconds]

If &lt;setpos> evaluates to *true* then on exit the file descriptor &lt;fd> will be positioned to the end of the id3 tag, otherwise the file will be closed.


### id4.lua:

Similar to id3.lua, reads metadata from M4A (AAC) files.
Contains a single function **load(fd, coverart, rewind)** -> *table* or -> *nil, errormsg*

*fd* must be some kind of file object which implements the methods:

	read(n) - read the next <n> bytes from the file.
	seek(whence, offset) - posix-like seek, or the following three methods:
	seek(posn)
	tell() -> current posn
	getSize() -> file size
	
	
The file object must initially be positioned at the start of the file. 
The function returns a table containing the following fields (if found):

	CreatedBy [string]
	TrackName [string]
	Artist [string]
	Album [string]
	TrackNumber [number]
	Genre [string]
	Year [number]
	Length [in seconds]
	CoverArt [binary data]

The *CoverArt* entry is only returned if &lt;coverart> evaluates to *true*. If &lt;rewind> evaluates to *true* then on exit the file descriptor &lt;fd> will be repositioned to the start of the file, otherwise the file will be closed.


### app_debug.apk:

A slightly modified Android(ARM) love2d-app.
Adds the following functionality:

*love.filesystem._allowMountingForPath(path, where)*

This is an interface to the physfs function of the same name, which allows any directory in the filesystem to
be mounted for reading.

In addition, this apk checks for and runs */storage/extSdCard/lovegame/main.lua* if no other intent is given.


### lfs.so

Android/love2d build of the luafilesystem library.


