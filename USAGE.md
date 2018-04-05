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

If you would like to see some real-life examples, head to <http://photosite.pl> to see the gallery of the original author of the script, or to my gallery [Tomasz Golinski](http://tomaszg.pl/).

Quick start
---------

* Create a hierarchy of images. Each directory will become an album and it is possible to nest them. 
* Create main `album.dat` file (see the example file) specifying image sizes, number of columns and so on.
* Create `style.css` file by customizing the attached sample file.
* Add `album.dat` files to albums. It should consist at least of tags: `TITLE:`, `HIGHLIGHT:` and mask of files to be included (e.g. `+*jpg`). You may add some additional data, see the section below.
* Run the gallery script. By default it creates a directory `html` with the gallery files (html, images, thumbnails, CSS).

Script accepts the following parameters, all of them optional:

 * `-o output_dir` output directory where the gallery will be placed, default: `html`
 * `-u update_dir` enables update mode, script parses only part of the gallery under specified album 
 * `-h` displays short options summary
 * `-s` automatically run script called `sync`, which is supposed to be responsible for uploading gallery to the server
 * `-r`renames all processed image files according to the pattern `i%Y%m%d_%H%M%S`. Works only with `-u`.

LOCAL_ and non-LOCAL_
---------------------

Sometimes you will find some parameters that have two versions. Let's take `LOCAL_THUMB_SIZE` and `THUMB_SIZE` as an example. The rules are the following:

*   In the given album (but not in sub-albums) `LOCAL` overrides non-`LOCAL`
*   In the sub-albums, non-`LOCAL` settings are copied from the parent ones. `LOCAL` ones - aren't

The idea behind such approach is the following: Imagine that one of your albums is a gallery from the music festival (look [here](http://photosite.pl/events/gena05) to see one). You would like to have four sub-galleries, from different parts of the concert, with big thumbnails on the main page and 2x2 layout. However, inside the sub-galleries, you'd prefer to keep the consistent 4 columns layout, with relatively small thumbnails. What you do? In the main festival gallery you specify:

*   `LOCAL` options for the festival gallery index (bigger thumbnails, 2 columns)
*   non-`LOCAL` options that will be applied to sub-galleries

Tag reference
-------------

* `\# ...` Line beginning with `#` is treated as a comment and ignored

* `TITLE: _string_` Title of the gallery

* `DATE: _string_` What you want to put in the top-right corner. Note that some reasonable defaults are used, like the EXIF info or the directory creation time. What's more, if you try to specify manually some date and there will be image **newer** than this date in the album - its date will be used

* `BREAK: _string_` Spacer between groups of images

* `ABOUT: _string_` File to put in the "about the author" link on the bottom of each page. This works a bit like the CSS tag below, in a sense that it's inherited by all the sub-levels (however, there is just one file that can be put there).

* `RSS_BASE: _url_` If specified, causes the RSS to be generated, with the given URL (needs to be complete, http://...) as a base

* `CSS: _filename_  `, `LOCAL_CSS: _filename_` CSS file to use. You just need to put them in the same directory as album.dat, the HTML links will be arranged properly. Note that the style sheets are really 'cascading' - this means, that if you've had some `CSS` tags on the upper levels of your hierarchy, the HTML links to them will be generated.

* `HIGHLIGHT: _filename_` By default, the thumbnail of a gallery is generated from the first image on a page. Here you can specify another one

* `COLUMNS: _number_  `, `LOCAL_COLUMNS: _number_` Number of columns on page

* `TABLE_WIDTH: _number_` What to put as "width" in HTML

* `IMAGE_SIZE: _NNNxNNN_ `, `LOCAL\_IMAGE\_SIZE: _NNNXNNN_` Full size image resolution

* `ALBUM_SIZE: _NNNxNNN_`, `LOCAL\_ALBUM\_SIZE: _NNNXNNN_` Resolution for thumbnails of the albums

* `THUMB_SIZE: _NNNxNNN_`, `LOCAL\_THUMB\_SIZE: _NNNXNNN_` Resolution for thumbnails of the images

* `META_KEYWORDS: _string_`, `LOCAL\_META\_KEYWORDS: _string_` Strings to put in the HTML header. Name of the gallery and the upper-level galleries are always included.

* `UNSHARP: _geometry_` Optional Unsharp Mask (ImageMagick syntax)

* `GAMMA: _float_` Optional gamma conversion

* `IMAGE_QUALITY: _integer_` JPG quality for full size images

* `THUMB_QUALITY: _integer_` JPG quality for album/image thumbnails

* `OPTIONS:  option, option, ...` Triggers for options. Currently recognized:

*  `noexif` - disable display of the EXIF information _(default)_
*   `exif` - enable display of the EXIF information
*   `noconv` - disable conversion of the big images (they will be copied directly)
*   `conv` - enable conversion of the big images _(default)_
*   `hidden` - this album will not show up in the upper-level album lists
*   `leaf` - include this album in RSS
*   `count` - include number of images [N] in album name
*   `count_dir` - include number of directories (N) in album name, including links but excluding hidden

* `LENS: _XX-YY description_` Define a lens for the EXIF recognition. The script can often detect the zoom range of the lens, but not the exact model - it's a way to help it. The best practice is to put all your lenses in the main album.dat of the gallery

* `HEADER: _string_`, `FOOTER: _string_`, `LOCAL_FOOTER: _string_` Text for the top and the bottom line of the page

* `BANDS: _name_ _url_ _string_` Support for placing a link to `_url_` on all albums with directory `_name_`. Last string is description to be put there.

* `ISTATS:` Legacy option supporting deprecated statistics gathering engine

* `+_mask_` Include all the files/directories that match the _mask_ (unix shell regexp)

* `r+_mask_` Include all the files/directories that match the _mask_ **in reverse order** (unix shell regexp)

* `@_url_;_string_` Include link to an existing gallery/image located at `_url_` with title `_string_`. Thumbnail is expected to be available in a default location for this script

* `_string_` Everything else is treated as the dirname/filename to include

Misc. notes
-----------

### Other metadata files

* If the directory contains a file called `about.html`, link to that file will replace navigation links in the top right corner.

* If the directory contains files with the same name as image with extra suffix `.txt`, its contents will be added to the page for that image.

### EXIF and lens info

EXIF tags are analyzed using the Perl library, some tricks are used to make the display look good, depending on how much information the camera provides. However, in order to reliably detect the lens used, some heuristics is needed. Hints for the heuristics is provided using the `LENS` tag in the configuration file.

### Image cache

During the generation of thumbnails/images, the script generates (and maintains) some additional metatada, stored in the target directory, to avoid repetitive conversion of the same images. However, this mechanism is not perfect. Once in a while it's a good idea to regenerate all the gallery from scratch.

### HTML

While the CSS files are customizable, the generated HTML is not. It's created entirely from Perl and there is no plan to implement any templates in a near future.

### Speed

The main bottleneck is the creation of images/thumbnails. With caching enabled that is no longer the issue but still the script can take long time to process a big gallery. However there is a update mode that limits the script to work only on one top-level albums of the gallery.

Download
--------

To grab the code, go to <https://github.com/tomaszg7/gallery>. The original script is available at <http://sgallery.sourceforge.net/>.

(C) 2006 Daniel Rychcik (muflon /at/ ais /dot/ pl)
(C) 2006-2018 Tomasz Goliński (tomaszg@math.uwb.edu.pl)
