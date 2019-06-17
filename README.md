# love
Odds'n'ends for Löve (love2d) projects


id3.lua:

Module to read ID3 tags from mp3 files.
Contains a single function load(fd) -> <table>

fd must be some kind of file object which implements the method read(n) to read the next <n> bytes from the file.
The file object must initially be positioned at the start of the file. 
The function returns a table containing the following fields (if found):




app_debug.apk:

A slightly modified Android(ARM) love2d-app.
Adds the following functionality:

love.filesystem._allowMountingForPath(path, where)

This is an interface to the physfs function of the same name, which allows any directory in the filesystem to
be mounted for reading.



lfs.so

Android/love2d build of the luafilesystem library.


