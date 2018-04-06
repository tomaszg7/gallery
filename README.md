Gallery - Perl script generating a static photo gallery
========

Static Web image gallery system. It is a fork of unmaintained [sgallery](http://sgallery.sourceforge.net/) by Daniel Rychcik (muflon /at/ photosite /dot/ pl). It adds new features and fixes some bugs.


Introduction
------------

This is neither "drag and drop" nor "plug and play" thing. There are few things to learn, config files to be written, you might need some additional software, etc. This is probably UNIX-only (or at least quite difficult to make it run under Windows). If you are looking for something that will "just work" and don't care that much about the details - it might not be what you want (however it might work for you). If you are a geek that likes the command-line, file-driven kind of stuff - read on :) 

What we've got here is a Perl script. It requires:

*   Image::ExifTool
*   Image::Magick
*   URI::Escape
*   Cwd
*   DateTime
*   File::Copy
*   File::Basename
*   File::stat
*   Storable

If you would like to see some real-life examples, head to <http://photosite.pl> to see the gallery of the original author of the script, or to my gallery [Tomasz Goliński](http://tomaszg.pl/).

Quick start
---------

* Create a hierarchy of images. Each directory will become an album and it is possible to nest them. 
* Create main `album.dat` file (see the example file) specifying image sizes, number of columns and so on.
* Create `style.css` file by customizing the attached sample file.
* Add `album.dat` files to albums. It should consist at least of tags: `TITLE:`, `HIGHLIGHT:` and mask of files to be included (e.g. `+*jpg`). You may add some additional data, see the section below.
* Run the gallery script. By default it creates a directory `html` with the gallery files (html, images, thumbnails, CSS).

See the [USAGE](USAGE.md) file for details.

(C) 2006 Daniel Rychcik (muflon /at/ ais /dot/ pl)  
(C) 2006-2018 Tomasz Goli?ski (tomaszg@math.uwb.edu.pl)
