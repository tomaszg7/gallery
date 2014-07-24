#!/usr/bin/perl

# 
#  skrypt muflona 
#  przerobiony tak,ze: 

# 1.5.2
#  1. bug z zlym dzialanie thumb_quality
# 1.5.1
#  1. opcja ISTATS
# 1.5.0
#  upgrade do wersji sgallery-0.5, zmiany w stosunku do oryginalu:
#   1. dodanie metering i EV do exifa dla innych aparatow niz 1D
#   2. jesli w katalogu znajduje sie plik about.html to ZAMIAST Prev,Up,Next bedzie About Author 
#   3. jesli w katalogu znajduje sie plik nazwa_pliku_graficznego.txt (konczacego sie na txt) to  
#      zawartosc tego pliku zostaje dopisana do strony z ta konkretna fotka 
#   4. obok about tworzy statsy 
#   5. dodanie "alt" do tagow "img" 
#   6. godzina z exifa do daty 
#   7. uwzglednia zmienna header
#   8. nazwy  .jpg.html
#   9. bug z noconv

use strict;
use Image::ExifTool;
use Image::Magick;
use URI::Escape;
use Cwd;
use DateTime;
use File::Copy;
use File::Basename;
use File::Compare;
use File::Temp;
use File::stat;

my $exifTool = new Image::ExifTool;

##########################################
package Cache;

# Tab delimited files:  local_image(w/o path) source_image size
# Stored as two assoc. arrays local_image, containing "source

sub new {
  shift;
  my $filename = shift;

  my $self = {};
  $self->{DATA} = {};
  $self->{DIRTY} = undef;
  bless $self;

  if ( -f $filename ) {
    open (my $file, $filename);
    while (<$file>) {
       if (/(.+)\t(.+)\t(.+)\t(.+)\t(.+)\t(.+)/) {
         $self->{DATA}{$1} = $2."\t".$3."\t".$4."\t".$5."\t".$6;
        chomp $self->{DATA}{$1};
      }
    }
    close $file;
  }

  return $self;
}

sub match {
  my $self = shift;
  my $src_image = shift;
  my $local_image = shift;
  my $image_size = shift;
  my $gamma = shift;
  my $unsharp = shift;
  my $quality = shift;
  if (!$gamma) { $gamma = "undef"; }
  if (!$unsharp) { $unsharp = "undef"; }

  if ( ($self->{DATA}{$local_image} eq $src_image."\t".$image_size."\t".$gamma."\t".$unsharp."\t".$quality) ) {
    return 1;
  } else {
    return undef;
  }
}


sub update {
  my $self = shift;
  my $src_image = shift;
  my $local_image = shift;
  my $image_size = shift;
  my $gamma = shift;
  my $unsharp = shift;
  my $quality = shift;
  if (!$gamma) { $gamma = "undef"; }
  if (!$unsharp) { $unsharp = "undef"; }

  $self->{DATA}{$local_image} = $src_image."\t".$image_size."\t".$gamma."\t".$unsharp."\t".$quality;
  $self->{DIRTY} = "y";
}

sub write {
  my $self = shift;
  my $filename = shift;

  if ($self->{DIRTY}) {
    open FILE, ">$filename";
    my $key;
    foreach $key ( keys %{$self->{DATA}} ) {
      print FILE $key."\t".$self->{DATA}{$key}."\n";
    }
    close FILE;
  }
}




##########################################
package Settings;

sub new {
  shift;

  my $self = {};
  # Not-modifiable through settings file
  $self->{OBJECT} = "settings";
  $self->{DATAFILE} = "album.dat";
  $self->{CHARSET} = "ISO-8859-2";
  $self->{IMAGES_DIR} = "images";
  $self->{THUMBS_DIR} = "thumbs";
  $self->{DEFAULT_ALBUM_TITLE} = "Untitled album";
  $self->{LINK_UP} = "Up";
  $self->{LINK_PREV} = "Previous";
  $self->{LINK_NEXT} = "Next";
  $self->{LINK_ABOUT} = "About the author";
  $self->{LINK_RSS} = "RSS feed";
  $self->{RSS_FILE} = "rss.xml";
  $self->{TREE_SEPARATOR} = "&diams;";

  $self->{FOOTER} = "";
  $self->{HEADER} = "&nbsp;";
  $self->{OPTIONS_EXIF} = undef;
  $self->{OPTIONS_NOCONV} = undef;
  $self->{OPTIONS_HIDDEN} = undef;
  $self->{FORCE_IMAGES} = undef;
  $self->{LENSES} = ();
  $self->{HIGHLIGHT} = "highlight.jpg";
  $self->{CSS_FILE} = undef;
  $self->{LOCAL_CSS_FILE} = undef;
  $self->{ABOUT_FILE} = undef;
  $self->{TABLE_WIDTH} = 995;
  $self->{IMAGE_SIZE} = "900x600";
  $self->{LOCAL_IMAGE_SIZE} = undef;
  $self->{ALBUM_SIZE} = "300x200";
  $self->{LOCAL_ALBUM_SIZE} = undef;
  $self->{THUMB_SIZE} = "231x154";
  $self->{LOCAL_THUMB_SIZE} = undef;
  $self->{COLUMNS} = "auto";
  $self->{LOCAL_COLUMNS} = undef;
  $self->{META_KEYWORDS} = "";
  $self->{LOCAL_META_KEYWORDS} = "";
  $self->{GAMMA} = undef;
  $self->{UNSHARP} = undef;
  $self->{IMAGE_QUALITY} = 90;
  $self->{THUMB_QUALITY} = 80;
  $self->{RSS_BASE} = undef;
  $self->{ISTATS} = undef;

  bless $self;

  return $self;
}

sub clone {
  my $self = shift;
  my $clone = { %$self }; 
  $clone->{CSS_FILE} = undef;
  $clone->{LOCAL_CSS_FILE} = undef;
  $clone->{ABOUT_FILE} = undef;
  $clone->{LOCAL_IMAGE_SIZE} = undef;
  $clone->{LOCAL_ALBUM_SIZE} = undef;
  $clone->{LOCAL_THUMB_SIZE} = undef;
  $clone->{LOCAL_COLUMNS} = undef;
  $clone->{LOCAL_META_KEYWORDS} = undef;
  $clone->{HIDDEN} = undef;
  bless $clone, ref $self;
}


##########################################
package Image;

sub new {
  shift;

  my $self = {};
  $self->{OBJECT} = "image";
  $self->{FILENAME} = shift;
  $self->{BASENAME} = File::Basename::basename($self->{FILENAME},());
  #File::Basename::basename($self->{FILENAME},('.jpg','.jpeg','.JPG','.JPEG'));
  $self->{TITLE} = shift;
  $self->{DATE} = undef;
  my $settings = shift;
  bless $self;

  my $info = $exifTool->ImageInfo($self->{FILENAME});

  if ($$info{CreateDate}) {
    $self->{DATE} = DateTime->new( year=>substr($$info{CreateDate},0,4),
                                   month=>substr($$info{CreateDate},5,2),
                                   day=>substr($$info{CreateDate},8,2),
                                   hour=>substr($$info{CreateDate},11,2),
                                   minute=>substr($$info{CreateDate},14,2),
                                   second=>substr($$info{CreateDate},17,2),
                                   nanosecond=>0, time_zone=>"floating");
  }
  if ($$info{Model}) {
    my $exif = $$info{Model};
    if ($$info{ShutterSpeed} && $$info{FocalLength} && $$info{Aperture}) {
      if ($$info{'ISO (1)'}) { $exif .= ", ISO".$$info{'ISO (1)'}; }
      elsif ($$info{'ISO'}) { $exif .= ", ISO".$$info{'ISO'}; }

      if ($$info{ShutterSpeed}) { $exif .= ", ".$$info{ShutterSpeed}."s"; }
      my $show_focal = 1;

      if (($$info{ShortFocal} == $$info{LongFocal}) && ($$info{ShortFocal} >1)) {
        $show_focal = undef;
      }
      $_ = $$info{ShortFocal}."-".$$info{LongFocal};

      my $lens = $settings->{LENSES}{$$info{ShortFocal}."-".$$info{LongFocal}};
      if ($lens) {
        $exif .= "<br>".$lens." ";
      } else {
        $exif .= ", ";
        $show_focal = 1;
      }
      if ($show_focal) { 
        $_ = $$info{FocalLength};
        if (/(.*)\..*/) {
          $exif .= $1."mm";
        }
      }
      if ($$info{Aperture}) { $exif .= ", f/".$$info{Aperture}; }

      if ($$info{MeteringMode} && $$info{ExposureProgram}) {
        $exif .= "<br>".$$info{ExposureProgram};
        if ($$info{ExposureCompensation} != 0) {
          $exif .= " (".$$info{ExposureCompensation}."EV)";
        }
        $exif .= ", ".$$info{MeteringMode}." metering";
      }
      elsif ($$info{MeteringMode} && $$info{CanonExposureMode}) {
        $exif .= "<br>".$$info{CanonExposureMode};
        $exif .= ", ".$$info{MeteringMode}." metering";
        $exif .= " ".$$info{ExposureCompensation}."EV";
      }



    }
    $self->{EXIF_STRING} = $exif;
  }

  return $self;
}




##########################################
package Break;

sub new {
  shift;
  my $title = shift;

  my $self = {};
  $self->{OBJECT} = "break";
  $self->{TITLE} = $title;
  bless $self;
  return $self;
}



##########################################
package Album;

sub new {
  shift;
  my $directory = shift;

  my $self = {};
  $self->{OBJECT} = "album";
  $self->{DIRECTORY} = $directory;
  $self->{DIRNAME} = basename($directory);
  $self->{TITLE}=$self->{DIRNAME};
  $self->{DATE} = undef;
  $self->{PARENT_ALBUM} = shift;
  $self->{ENTRIES} = ();
  $self->{N_ENTRIES} = 0;
  $self->{N_IMAGES} = 0;
  $self->{CONTAINS_ALBUMS} = undef;
  $self->{SETTINGS} = shift;
  $self->{NEST} = shift;
  $self->{URL_PATH} = "";
  if ($self->{PARENT_ALBUM}) {
    if ($self->{PARENT_ALBUM}->{URL_PATH} ne "") {
      $self->{URL_PATH} = $self->{PARENT_ALBUM}->{URL_PATH}."/".$self->{DIRNAME};
    } else {
      $self->{URL_PATH} = $self->{DIRNAME};
    }
  }
  bless $self;

  $self->{INDENT} = "";
  for my $n (1 .. $self->{NEST}) {
    $self->{INDENT} = "  ".$self->{INDENT};
  }

  my $pushd = pwd();
  chdir $directory;

  my $css_basename = undef;
  my $local_css_basename = undef;

$self->debug(1,"Initializing new album in: \"".$directory."\"");
  if (open my $datafile, $self->{SETTINGS}->{DATAFILE}) {
    while (<$datafile>) {
      chomp;
      if (/^#(.*)/) {
$self->debug(1,"  Skipping comment:  ".$1);
      }
      elsif (/^[A-Z0-9_]+:.*/) {
        if (/^TITLE:\s+(.+)/) {
          $self->{TITLE} = $1;
$self->debug(1,"  Read TITLE: \"".$self->{TITLE}."\"");
        }
        elsif (/^DATE:\s+(.+)/) {
          $self->{DATE} = DateTime->new( year=>substr($1,6,4),
                                         month=>substr($1,3,2),
                                         day=>substr($1,0,2),
                                         hour=>0, minute=>0, second=>0,
                                         nanosecond=>0, time_zone=>"floating");
$self->debug(1,"  Read custom DATE");
        }
        elsif (/^OPTIONS:\s+(.+)/) {
          my(@options) = split(',',$1);
          for (@options) {
            if (/\s*noexif\s*/) {
              $self->{SETTINGS}->{OPTIONS_EXIF} = undef;
$self->debug(1,"  Disabled EXIF data display");
            }
            elsif (/\s*exif\s*/) {
              $self->{SETTINGS}->{OPTIONS_EXIF} = "y";
$self->debug(1,"  Enabled EXIF data display");
            }
            elsif (/\s*noconv\s*/) {
              $self->{SETTINGS}->{OPTIONS_NOCONV} = "y";
$self->debug(1,"  Enabled direct image copy");
            }
            elsif (/\s*conv\s*/) {
              $self->{SETTINGS}->{OPTIONS_NOCONV} = undef;
$self->debug(1,"  Disabled direct image copy");
            }
            elsif (/\s*hidden\s*/) {
              $self->{SETTINGS}->{OPTIONS_HIDDEN} = "y";
$self->debug(1,"  Hiding this album in the upper-level listing");
            }
          }
        }
        elsif (/^LENS:\s+(\S+)\s+(\S.*)/) {
          $self->{SETTINGS}->{LENSES}{$1} = $2;
$self->debug(1,"  Read lens: ".$1." == ".$2);
        }
        elsif (/^BREAK:\s?(.*)/) {
          my $title = $1;
          my $break = Break->new($title);
          push @{$self->{ENTRIES}}, $break;
$self->debug(1,"  Read BREAK: \"".$title."\"");
        }
        elsif (/ABOUT:\s+(.+)\s*/) {
          $self->{SETTINGS}->{ABOUT_FILE} = $directory."/".$1;
$self->debug(1,"  Read ABOUT: \"".$self->{SETTINGS}->{ABOUT_FILE}."\"");
          $css_basename = basename($self->{SETTINGS}->{ABOUT_FILE});
        }
        elsif (/LOCAL_CSS:\s+(.+)\s*/) {
          $self->{SETTINGS}->{LOCAL_CSS_FILE} = $directory."/".$1;
$self->debug(1,"  Read LOCAL_CSS: \"".$self->{SETTINGS}->{LOCAL_CSS_FILE}."\"");
          $local_css_basename = basename($self->{SETTINGS}->{LOCAL_CSS_FILE});
        }
        elsif (/CSS:\s+(.+)\s*/) {
          $self->{SETTINGS}->{CSS_FILE} = $directory."/".$1;
$self->debug(1,"  Read CSS: \"".$self->{SETTINGS}->{CSS_FILE}."\"");
          $css_basename = basename($self->{SETTINGS}->{CSS_FILE});
        }
        elsif (/HIGHLIGHT:\s+(.+)\s*/) {
          $self->{SETTINGS}->{HIGHLIGHT} = $1;
          chomp $self->{SETTINGS}->{HIGHLIGHT};
$self->debug(1,"  Read HIGHLIGHT: \"".$self->{SETTINGS}->{HIGHLIGHT}."\"");
        }
        elsif (/RSS_BASE:\s+(.+)\s*/) {
          $self->{SETTINGS}->{RSS_BASE} = $1;
          chomp $self->{SETTINGS}->{RSS_BASE};
$self->debug(1,"  Read RSS_BASE: \"".$self->{SETTINGS}->{RSS_BASE}."\"");
        }
        elsif (/LOCAL_COLUMNS:\s+([123456789])\s*/) {
          $self->{SETTINGS}->{LOCAL_COLUMNS} = $1;
$self->debug(1,"  Read LOCAL_COLUMNS: \"".$self->{SETTINGS}->{LOCAL_COLUMNS}."\"");
        }
        elsif (/TABLE_WIDTH:\s+([0123456789]*)\s*/) {
          $self->{SETTINGS}->{TABLE_WIDTH} = $1;
$self->debug(1,"  Read TABLE_WIDTH: \"".$self->{SETTINGS}->{TABLE_WIDTH}."\"");
        }
        elsif (/COLUMNS:\s+([123456789])\s*/) {
          $self->{SETTINGS}->{COLUMNS} = $1;
$self->debug(1,"  Read COLUMNS: \"".$self->{SETTINGS}->{COLUMNS}."\"");
        }
        elsif (/LOCAL_IMAGE_SIZE:\s+(\S*)\s*/) {
          $self->{SETTINGS}->{LOCAL_IMAGE_SIZE} = $1;
          chomp $self->{SETTINGS}->{LOCAL_IMAGE_SIZE};
$self->debug(1,"  Read LOCAL_IMAGE_SIZE: \"".$self->{SETTINGS}->{LOCAL_IMAGE_SIZE}."\"");
        }
        elsif (/IMAGE_SIZE:\s+(\S*)\s*/) {
          $self->{SETTINGS}->{IMAGE_SIZE} = $1;
          chomp $self->{SETTINGS}->{IMAGE_SIZE};
$self->debug(1,"  Read IMAGE_SIZE: \"".$self->{SETTINGS}->{IMAGE_SIZE}."\"");
        }
        elsif (/LOCAL_ALBUM_SIZE:\s+(\S*)\s*/) {
          $self->{SETTINGS}->{LOCAL_ALBUM_SIZE} = $1;
          chomp $self->{SETTINGS}->{LOCAL_ALBUM_SIZE};
$self->debug(1,"  Read LOCAL_ALBUM_SIZE: \"".$self->{SETTINGS}->{LOCAL_ALBUM_SIZE}."\"");
        }
        elsif (/ALBUM_SIZE:\s+(\S*)\s*/) {
          $self->{SETTINGS}->{ALBUM_SIZE} = $1;
          chomp $self->{SETTINGS}->{ALBUM_SIZE};
$self->debug(1,"  Read ALBUM_SIZE: \"".$self->{SETTINGS}->{ALBUM_SIZE}."\"");
        }
        elsif (/LOCAL_THUMB_SIZE:\s+(\S*)\s*/) {
          $self->{SETTINGS}->{LOCAL_THUMB_SIZE} = $1;
          chomp $self->{SETTINGS}->{LOCAL_THUMB_SIZE};
$self->debug(1,"  Read LOCAL_THUMB_SIZE: \"".$self->{SETTINGS}->{LOCAL_THUMB_SIZE}."\"");
        }
        elsif (/THUMB_SIZE:\s+(\S*)\s*/) {
          $self->{SETTINGS}->{THUMB_SIZE} = $1;
          chomp $self->{SETTINGS}->{THUMB_SIZE};
$self->debug(1,"  Read THUMB_SIZE: \"".$self->{SETTINGS}->{THUMB_SIZE}."\"");
        }
        elsif (/LOCAL_META_KEYWORDS:\s+(\S.*)\s*$/) {
          $self->{SETTINGS}->{LOCAL_META_KEYWORDS} = $1;
          chomp $self->{SETTINGS}->{LOCAL_META_KEYWORDS};
$self->debug(1,"  Read LOCAL_META_KEYWORDS: \"".$self->{SETTINGS}->{LOCAL_META_KEYWORDS}."\"");
        }
        elsif (/META_KEYWORDS:\s+(\S.*)\s*$/) {
          $self->{SETTINGS}->{META_KEYWORDS} = $1;
          chomp $self->{SETTINGS}->{META_KEYWORDS};
$self->debug(1,"  Read META_KEYWORDS: \"".$self->{SETTINGS}->{META_KEYWORDS}."\"");
        }
        elsif (/FOOTER:\s+(\S.*\S)\s*$/) {
          $self->{SETTINGS}->{FOOTER} = $1;
$self->debug(1,"  Read FOOTER: \"".$self->{SETTINGS}->{FOOTER}."\"");
        }
      elsif (/HEADER:\s+(.+)/) {
        $self->{SETTINGS}->{HEADER} = $1;
          chomp $self->{SETTINGS}->{HEADER};
$self->debug(1,"  Read HEADER: \"".$self->{SETTINGS}->{HEADER}."\"");
      }
      elsif (/ISTATS:\s+(.+)/) {
        $self->{SETTINGS}->{ISTATS} = $1;
          chomp $self->{SETTINGS}->{ISTATS};
$self->debug(1,"  Read ISTATS: \"".$self->{SETTINGS}->{ISTATS}."\"");
      }
        elsif (/GAMMA:\s+(\S.*)\s*$/) {
          $self->{SETTINGS}->{GAMMA} = $1;
          chomp $self->{SETTINGS}->{GAMMA};
$self->debug(1,"  Read GAMMA: \"".$self->{SETTINGS}->{GAMMA}."\"");
        }
        elsif (/UNSHARP:\s+(\S.*)\s*$/) {
          $self->{SETTINGS}->{UNSHARP} = $1;
          chomp $self->{SETTINGS}->{UNSHARP};
$self->debug(1,"  Read UNSHARP: \"".$self->{SETTINGS}->{UNSHARP}."\"");
        }
        elsif (/IMAGE_QUALITY:\s+(\S.*)\s*$/) {
          $self->{SETTINGS}->{IMAGE_QUALITY} = $1;
          chomp $self->{SETTINGS}->{IMAGE_QUALITY};
$self->debug(1,"  Read IMAGE_QUALITY: \"".$self->{SETTINGS}->{IMAGE_QUALITY}."\"");
        }
        elsif (/THUMB_QUALITY:\s+(\S.*)\s*$/) {
          $self->{SETTINGS}->{THUMB_QUALITY} = $1;
          chomp $self->{SETTINGS}->{THUMB_QUALITY};
$self->debug(1,"  Read THUMB_QUALITY: \"".$self->{SETTINGS}->{THUMB_QUALITY}."\"");
        }

      }
      elsif (/\+(.+)\s*/) {
        my $mask = $1; chomp $mask;
$self->debug(1,"  Including from mask: \"".$mask."\"");

        for my $filename (sort(glob($mask))) {
          if ( -d $filename ) {
$self->debug(1,"    Directory: \"".$filename."\"");
            my $album = Album->new($directory."/".$filename, $self, $self->{SETTINGS}->clone(), $self->{NEST}+3);
            push @{$self->{ENTRIES}}, $album;
            $self->{CONTAINS_ALBUMS} = "y";
            if ($album->{DATE}) {
              $self->update_date_if_newer($album->{DATE});
            }
            if ($filename eq $self->{SETTINGS}->{HIGHLIGHT}) {
              $self->{HIGHLIGHT} = $album->{HIGHLIGHT};
            }
          } elsif ((-f $filename) && ($filename ne $self->{SETTINGS}->{DATAFILE}) && ($filename ne $css_basename) && ($filename ne $local_css_basename) && !($filename =~ /txt$/)) {
$self->debug(5,"    File: \"".$filename."\"");
            my $image = Image->new($directory."/".$filename, undef, %$self->{SETTINGS});
            $image->{IMAGE_INDEX} = $self->{N_IMAGES};
            $self->{N_IMAGES}++;
            push @{$self->{ENTRIES}}, $image;
            if ($image->{DATE}) {
              $self->update_date_if_newer($image->{DATE});
            }
            if ($filename eq $self->{SETTINGS}->{HIGHLIGHT}) {
              $self->{HIGHLIGHT} = $image;
            }
          }
        }
      }
      elsif (/\s*\S.*/) {
        my $highlight;
        my $filename;
        my $title;
        if (/^(!)?(.*);(.*)\S*/) {
          $highlight = $1;
          $filename = $2;
          $title = $3;
        } elsif (/^(!)?(.*)\S*/) {
          $highlight = $1;
          $filename = $2;
          $title = undef;
        }
        if ($filename eq $self->{SETTINGS}->{HIGHLIGHT}) {
          $highlight = "!";
        }

        chomp $filename;

        if ( -d $filename ) {
          my $album = Album->new($directory."/".$filename, $self, $self->{SETTINGS}->clone(), $self->{NEST}+1);
          push @{$self->{ENTRIES}}, $album;
          $self->{CONTAINS_ALBUMS} = "y";
          if ($album->{DATE}) {
            $self->update_date_if_newer($album->{DATE});
          }
          if ($highlight eq "!") {
            $self->{HIGHLIGHT} = $album->{HIGHLIGHT};
          }
        } elsif ((-f $filename) && ($filename ne $self->{SETTINGS}->{DATAFILE}) && ($filename ne $css_basename) && ($filename ne $local_css_basename)) {
          my $image = Image->new($directory."/".$filename, $title, %$self->{SETTINGS});
          $image->{IMAGE_INDEX} = $self->{N_IMAGES};
          $self->{N_IMAGES}++;
          push @{$self->{ENTRIES}}, $image;
          if ($image->{DATE}) {
            $self->update_date_if_newer($image->{DATE});
          }
          if ($highlight eq "!") {
            $self->{HIGHLIGHT} = $image;
          }
        } elsif ( ! -z $_ ) {
$self->debug(1,"  Unknown entry in ".$directory."/".$self->{SETTINGS}->{DATAFILE}."(".$_.")");
        }

      }
    }
    close $datafile;
  } else {
$self->debug(1,"  No ".$self->{SETTINGS}->{DATAFILE}." found in \"".$directory."\" - reading contents.");
    $self->add_all_directories($directory);
    if ($self->{ENTRIES}[0]) {
$self->debug(1,"  Adding break between the directories and files section");
      my $break = Break->new(undef);
      push @{$self->{ENTRIES}}, $break;
    }
    $self->add_all_files($directory);
  }

  $self->{N_ENTRIES} = scalar (@{$self->{ENTRIES}});

  if (!$self->{HIGHLIGHT}) {
    my $entry = $self->{ENTRIES}[0];
    my $n = 0;
    while (($entry->{OBJECT} ne "image") && ($entry->{OBJECT} ne "album")) {
      $n++;
      if ($n >= $self->{N_ENTRIES}) {
        print ("No images nor directories in \"".$directory."\"!!! - aborting\n");
        die;
      }
      $entry = $self->{ENTRIES}[$n];
    }

    if ($entry->{OBJECT} eq "image") {
      $self->{HIGHLIGHT} = $entry;
    } elsif ($entry->{OBJECT} eq "album") {
      $self->{HIGHLIGHT} = $entry->{HIGHLIGHT};
    }
  }
$self->debug(5,"");

  chdir $pushd;
  return $self;
}

sub add_all_directories {
  my $self = shift;
  my $directory = shift;

  my $pushd = pwd();
  chdir $directory;

  for my $filename (sort(glob("*"))) {
    if ( (-d $filename) && ($filename ne ".") && ($filename ne "..")) {
$self->debug(1,"  Adding sub-directory \"".$filename."\"");
      my $album = Album->new($directory."/".$filename, $self, $self->{SETTINGS}->clone(), $self->{NEST}+1);
      push @{$self->{ENTRIES}}, $album;
    }
  }

  chdir $pushd;
}

sub add_all_files {
  my $self = shift;
  my $directory = shift;

  my $pushd = pwd();
  chdir $directory;

  for my $filename (sort(glob("*"))) {
    if ((-f $filename) && (substr($filename,0,1) ne ".")) {
$self->debug(5,"  Adding image \"".$filename."\"");
      my $image = Image->new($directory."/".$filename, undef, %$self->{SETTINGS});
      $image->{IMAGE_INDEX} = $self->{N_IMAGES};
      $self->{N_IMAGES}++;
      push @{$self->{ENTRIES}}, $image;
    }
  }
  chdir $pushd;
}

sub generate_index {
  my $self = shift;
  my $columns = shift;

  open my $oldout, ">&STDOUT";

  my $title = $self->{SETTINGS}->{DEFAULT_ALBUM_TITLE};
  if ($self->{TITLE}) {
    $title = $self->{TITLE};
  }

  my $date = $self->{DATE};
  if ($date) {
    $date = $date->strftime("%e-%m-%Y");
  } else {
    $date = "&nbsp;";
  }

  my $tmpnam = File::Temp::tmpnam();

  open STDOUT,">".$tmpnam;
  print ("<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">\n");
  print ("<html>\n");
  print (" <head>\n");
  print ("  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=".$self->{SETTINGS}->{CHARSET}."\">\n");
  $self->print_meta_keywords_tag();
  $self->style_link();
  $self->rss_meta();
  if ($self->{PARENT_ALBUM}) {
    print ("  <link rel=\"Contents\" href=\"../index.html\">\n");
  }
  print ("  <title>".$title."</title>\n");
  print ("  <script type=\"text/javascript\">\n");
  print ("    <!--\n");
  print ("      function getKey(event) {\n");
  print ("        if (!event) event = window.event;\n");
  print ("        if (event.keyCode) code = event.keyCode;\n");
  print ("        else if (event.which) code = event.which;\n");
  print ("        if (event.shiftKey) {\n");
  if ($self->{PARENT_ALBUM}) {
    print ("          if (code == 38) {\n");
    print ("            document.location = '../index.html';\n");
    print ("          }\n");
  }
  print ("        }\n");
  print ("        return true;\n");
  print ("      }\n");
  print ("      document.onkeypress = getKey;\n");
  print ("    // -->\n");
  print ("  </script>\n");
  print (" </head>\n");
  print (" <body>\n");
  if ($self->{SETTINGS}->{HEADER} ne "&nbsp;"){ 
  print ($self->{SETTINGS}->{HEADER}."\n");} 
  print ("  <table style=\"width: ".$self->{SETTINGS}->{TABLE_WIDTH}."px;\" cellspacing=\"0\">\n");
  print ("   <tr>\n");
  print ("    <td".colspan($columns-1)." class=\"title\">".$title."</td>\n");
  print ("    <td class=\"date\">".$date."</td>\n");
  print ("   </tr>\n");
  print ("   <tr>\n");
  print ("    <td".colspan($columns-1)." class=\"parent_links\">\n");
  $self->print_parent_links(0, "n");
  print ("    </td>\n");
  print ("    <td class=\"nav_links\">\n");
  if ( -f "about.html"){ 
    print ("  <a href=\"../cgi-bin/stats.cgi\">Most viewed</a>&nbsp;&nbsp;&nbsp;   <a href=\"about.html\">About ".$self->{TITLE}."</a>\n");
    } 
  else{
  print ("     ".$self->{SETTINGS}->{LINK_PREV}."&nbsp;&nbsp;&nbsp;");
  if ($self->{PARENT_ALBUM}) {
    print ("<a href=\"../index.html\">".$self->{SETTINGS}->{LINK_UP}."</a>");
  } else {
    print ($self->{SETTINGS}->{LINK_UP});
  }
  print ("&nbsp;&nbsp;&nbsp;".$self->{SETTINGS}->{LINK_NEXT}."\n");
  }
  print ("    </td>\n");
  print ("   </tr>\n");

  my $n = 0;
  ROWS: while ($n < $self->{N_ENTRIES}) {
    print ("   <tr>\n");
    my $col = 0;
    COLS: while ($col < $columns) {
      if ($self->{ENTRIES}[$n]) {
        if ( $self->{ENTRIES}[$n]->{OBJECT} eq "break" ) {
          if ($col > 0) {
            print ("    <td ".width($columns)." ".colspan($columns - $col)." class=\"thumb_empty\">&nbsp;</td>\n");
            print ("   </tr>\n");
            print ("   <tr>\n");
          }
          if ( length($self->{ENTRIES}[$n]->{TITLE}) > 0 ) {
            print ("    <td".colspan($columns)." class=\"break\">");
            print ($self->{ENTRIES}[$n]->{TITLE});
            print ("</td>\n");
          } else {
            print ("    <td".colspan($columns)." class=\"break_empty\">&nbsp;</td>\n");
          }
          print ("   </tr>\n");
          $n++;
          next ROWS;
        }
        elsif ( $self->{ENTRIES}[$n]->{OBJECT} eq "album" ) {
          if (!$self->{ENTRIES}[$n]->{SETTINGS}->{OPTIONS_HIDDEN}) {
            print ("    <td".width($columns)." class=\"thumb_album\">\n");
            print ("     <a href=\"".uri_escape($self->{ENTRIES}[$n]->{DIRNAME})."/index.html\">\n");
            print ("      <img class=\"thumb_album\" src=\"".$self->{SETTINGS}->{THUMBS_DIR}."/".uri_escape($self->{ENTRIES}[$n]->{DIRNAME}).".jpg\" alt=\"".$title."\">\n");
	    if ($self->{ENTRIES}[$n]->{TITLE}) {
              print ("      <br>".$self->{ENTRIES}[$n]->{TITLE}."\n");
            }
            print ("     </a>\n");
            print ("    </td>\n");
          } else {
            $col--;
	  }
          $n++;
        }
        elsif ( $self->{ENTRIES}[$n]->{OBJECT} eq "image" ) {
          print ("    <td".width($columns)." class=\"thumb_image\">\n");
          print ("     <a href=\"".uri_escape($self->{ENTRIES}[$n]->{BASENAME}).".html\">\n");
          print ("      <img alt=\"image\" class=\"thumb_image\" src=\"".$self->{SETTINGS}->{THUMBS_DIR}."/".uri_escape($self->{ENTRIES}[$n]->{BASENAME})."\">\n");
          if ($self->{ENTRIES}[$n]->{TITLE}) {
            print ("      <br>".$self->{ENTRIES}[$n]->{TITLE}."\n");
          }
          print ("     </a>\n");
          print ("    </td>\n");
          $n++;
        }
      } elsif ($n >= $self->{N_ENTRIES}) {
        print ("    <td".colspan($columns - $col)." class=\"thumb_empty\">&nbsp;</td>\n");
        $col = $columns;
      } else {
        print ("    <td class=\"thumb_empty\">&nbsp;</td>\n");
        $n++;
      }
      
      $col++;
    }
    print ("   </tr>\n");
  }
  print ("   <tr>\n");
  print ("    <td".colspan($columns)." class=\"footer\">\n");
  print ("     ".$self->{SETTINGS}->{FOOTER}."<br>\n");
  if ($self->{SETTINGS}->{ISTATS}) {
   print ("    <script type=\"text/javascript\">\n");
   print ("    <!-- \n");
   print ("    var ipath=\'".$self->{SETTINGS}->{ISTATS}."\'\n");  
   print ("    document.write(\'<SCR\' + \'IPT LANGUAGE=\"JavaScript\" SRC=\"http://\'+ ipath +\'/istats.js\"><\/SCR\' + \'IPT>\');\n");  
   print ("    //-->\n");
   print ("    </script><br>\n");
  }
  if ($self->about_link()) {
    if ($self->{SETTINGS}->{RSS_BASE}) {
      print ("     &nbsp;&nbsp;&diams;&nbsp;&nbsp;\n");
    }
  }
  $self->rss_link();
  print ("    </td>\n");
  print ("   </tr>\n");
  print ("  </table>\n");
  print (" </body>\n");
  print ("</html>\n");
  print "\n";
  close STDOUT;
  open STDOUT, ">&", $oldout;

  compare_and_copy($tmpnam, "index.html");
  unlink ($tmpnam);

}


sub generate_image {
  my $self = shift;
  my $n = shift;
  my $columns = shift;
  my $image = $self->{ENTRIES}[$n];

  my $date = $self->{DATE};
  if ($image->{DATE}) {
    $date = $image->{DATE};
  }
  if ($date) {
    $date = $date->strftime("%e-%m-%Y %k:%M");
  } else {
    $date = "&nbsp;";
  }

  my $prev_link = $n-1;
  FIND_PREV: while ($prev_link >=0) {
    if ($self->{ENTRIES}[$prev_link]->{OBJECT} eq "image") {
      last FIND_PREV;
    }
    $prev_link--;
  }

  my $next_link = $n+1;
  FIND_NEXT: while ($next_link < $self->{N_ENTRIES}) {
    if ($self->{ENTRIES}[$next_link]->{OBJECT} eq "image") {
      last FIND_NEXT;
    }
    $next_link++;
  }
  if ($next_link >= $self->{N_ENTRIES}) {
    $next_link = -1;
  }

  my $progress = ($image->{IMAGE_INDEX}+1)."/".$self->{N_IMAGES};

  my $title = "";
  if ($image->{TITLE}) {
    $title = $image->{TITLE};
  } else {
    $title = $self->{TITLE};
  }

  open my $oldout, ">&STDOUT";
  my $tmpnam = File::Temp::tmpnam();
  open STDOUT,">".$tmpnam;

  print ("<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">\n");
  print ("<html>\n");
  print (" <head>\n");
  print ("  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=".$self->{SETTINGS}->{CHARSET}."\">\n");
    $self->print_meta_keywords_tag();
    $self->style_link();
    $self->rss_meta();
    if ($prev_link >= 0) {
      print ("  <link rel=\"Prev\" href=\"".$self->{ENTRIES}[$prev_link]->{BASENAME}.".html\">\n");
    }
    print ("  <link rel=\"Contents\" href=\"index.html\">\n");
    if ($next_link >= 0) {
      print ("  <link rel=\"Next\" href=\"".$self->{ENTRIES}[$next_link]->{BASENAME}.".html\">\n");
    }
    print ("  <title>".$title."</title>\n");
    print ("  <script type=\"text/javascript\">\n");
    print ("    <!--\n");
    print ("      function getKey(event) {\n");
    print ("        if (!event) event = window.event;\n");
    print ("        if (event.keyCode) code = event.keyCode;\n");
    print ("        else if (event.which) code = event.which;\n");
    print ("        if (event.shiftKey) {\n");
    if ($prev_link >= 0) {
      print ("          if (code == 37) {\n");
      print ("            document.location = '".$self->{ENTRIES}[$prev_link]->{BASENAME}.".html';\n");
      print ("          }\n");
    }
    print ("          if (code == 38) {\n");
    print ("            document.location = 'index.html';\n");
    print ("          }\n");
    if ($next_link >= 0) {
      print ("          if (code == 39) {\n");
      print ("            document.location = '".$self->{ENTRIES}[$next_link]->{BASENAME}.".html';\n");
      print ("          }\n");
    } 
    print ("        }\n");
    print ("        return true;\n");
    print ("      }\n");
    print ("      document.onkeypress = getKey;\n");
    print ("    // -->\n");
    print ("  </script>\n");
    print (" </head>\n");
    print (" <body>\n");
    print ("  <table style=\"width: ".$self->{SETTINGS}->{TABLE_WIDTH}."px;\" cellspacing=\"0\">\n");
    print ("   <tr>\n");
    print ("    <td ".width(-$columns)." class=\"title\">".$title."</td>\n");
    print ("    <td ".width($columns)." class=\"date\">".$date."</td>\n");
    print ("   </tr>\n");
    print ("   <tr>\n");
    print ("    <td class=\"parent_links\">\n");
    $self->print_parent_links(0, "y");
    print ("     (".$progress.")\n");
    print ("    </td>\n");
    print ("    <td class=\"nav_links\">\n");
    if ($prev_link >= 0) {
      print ("     <a href=\"".uri_escape($self->{ENTRIES}[$prev_link]->{BASENAME}).".html\">".$self->{SETTINGS}->{LINK_PREV}."</a>");
    } else {
      print ("     ".$self->{SETTINGS}->{LINK_PREV});
    }
    print ("&nbsp;&nbsp;&nbsp;<a href=\"index.html\">".$self->{SETTINGS}->{LINK_UP}."</a>&nbsp;&nbsp;&nbsp;");
    if ($next_link >= 0) {
      print ("<a href=\"".uri_escape($self->{ENTRIES}[$next_link]->{BASENAME}).".html\">".$self->{SETTINGS}->{LINK_NEXT}."</a>\n");
    } else {
      print ($self->{SETTINGS}->{LINK_NEXT}."\n");
    } 
    print ("    </td>\n");
    print ("   </tr>\n");



    print ("   <tr>\n");
    print ("    <td class=\"image\" colspan=\"2\">\n");
    print ("     <img alt=\"image\" class=\"image\" src=\"".$self->{SETTINGS}->{IMAGES_DIR}."/".$image->{BASENAME}."\">\n");
    print ("    </td>\n");
    print ("   </tr>\n");
    if (-f $self->{ENTRIES}[$n]->{FILENAME}.".txt") {
        open(FILE, $self->{ENTRIES}[$n]->{FILENAME}.".txt");
        print ("    <tr><td colspan=\"2\" align=center class=\"break\">");
        while (<FILE>) {
        print ("$_\n");
        }
        print ("</td></tr>\n");
        close(FILE);
    }


    if ($image->{EXIF_STRING} && $self->{SETTINGS}->{OPTIONS_EXIF}) {
      print ("   <tr>\n");
      print ("    <td class=\"exif\" colspan=\"2\">\n");
      print ("     ".$image->{EXIF_STRING}."\n");
      print ("    </td>\n");
      print ("   </tr>\n");
    }

    print ("   <tr>\n");
    print ("    <td colspan=\"2\" class=\"footer\">\n");
    print ("     ".$self->{SETTINGS}->{FOOTER}."<br>\n");
  if ($self->{SETTINGS}->{ISTATS}) {
   print ("    <script type=\"text/javascript\">\n");
   print ("    <!-- \n");
   print ("    var ipath=\'".$self->{SETTINGS}->{ISTATS}."\'\n");  
   print ("    document.write(\'<SCR\' + \'IPT LANGUAGE=\"JavaScript\" SRC=\"http://\'+ ipath +\'/istats.js\"><\/SCR\' + \'IPT>\');\n");  
   print ("    //-->\n");
   print ("    </script><br>\n");
  }
    if ($self->about_link()) {
      if ($self->{SETTINGS}->{RSS_BASE}) {
        print ("     &nbsp;&nbsp;&diams;&nbsp;&nbsp;\n");
      }
    }
    $self->rss_link();
    print ("    </td>\n");
    print ("   </tr>\n");
    print ("  </table>\n");
    print (" </body>\n");
    print ("</html>\n");
    close STDOUT;
    open STDOUT, ">&", $oldout;

    compare_and_copy($tmpnam, $image->{BASENAME}.".html");
    unlink ($tmpnam);

  }


  sub generate {
    my $self = shift;
    my $directory = shift;

  $self->debug(1,"Generating structure for \"".$self->{TITLE}."\"");
    mkdir $directory;
    chdir $directory;

    mkdir $self->{SETTINGS}->{THUMBS_DIR};
    mkdir $self->{SETTINGS}->{IMAGES_DIR};

  $self->debug(1,"  Copying files");
    if ($self->{SETTINGS}->{CSS_FILE}) {
  $self->debug(1,"    Copying ".$self->{SETTINGS}->{CSS_FILE}."");
      copyToCwd($self->{SETTINGS}->{CSS_FILE});
    }
    if ($self->{SETTINGS}->{LOCAL_CSS_FILE}) {
  $self->debug(1,"    Copying ".$self->{SETTINGS}->{LOCAL_CSS_FILE}."");
      copyToCwd($self->{SETTINGS}->{LOCAL_CSS_FILE});
    }

    if ($self->{SETTINGS}->{ABOUT_FILE}) {
  $self->debug(1,"    Copying ".$self->{SETTINGS}->{ABOUT_FILE}."");
      copyToCwd($self->{SETTINGS}->{ABOUT_FILE});
    }

    my $thumb_size = $self->{SETTINGS}->{THUMB_SIZE};
    my $album_size = $self->{SETTINGS}->{ALBUM_SIZE};
    my $image_size = $self->{SETTINGS}->{IMAGE_SIZE};

    if ($self->{SETTINGS}->{LOCAL_IMAGE_SIZE}) {
      $image_size = $self->{SETTINGS}->{LOCAL_IMAGE_SIZE};
    }
    if ($self->{SETTINGS}->{LOCAL_ALBUM_SIZE}) {
      $album_size = $self->{SETTINGS}->{LOCAL_ALBUM_SIZE};
    }
    if ($self->{SETTINGS}->{LOCAL_THUMB_SIZE}) {
      $thumb_size = $self->{SETTINGS}->{LOCAL_THUMB_SIZE};
    }
    my $noconv = $self->{SETTINGS}->{OPTIONS_NOCONV};

    my $thumb_cache = Cache->new("thumbs/.cache");
    my $image_cache = Cache->new("images/.cache");

    for my $n (0 .. $self->{N_ENTRIES}-1) {
      my $src_image = undef;
    my $dest_thumb = undef;
    my $dest_image = undef;
    my $object_type = $self->{ENTRIES}[$n]->{OBJECT};
    if ($object_type eq "image") {
      $src_image = $self->{ENTRIES}[$n]->{FILENAME};
      $dest_thumb = $self->{SETTINGS}->{THUMBS_DIR}."/".$self->{ENTRIES}[$n]->{BASENAME};
      $dest_image = $self->{SETTINGS}->{IMAGES_DIR}."/".$self->{ENTRIES}[$n]->{BASENAME};
    } elsif ($object_type eq "album") {
      $src_image = $self->{ENTRIES}[$n]->{HIGHLIGHT}->{FILENAME};
      $dest_thumb = $self->{SETTINGS}->{THUMBS_DIR}."/".$self->{ENTRIES}[$n]->{DIRNAME}.".jpg";
      $dest_image = $self->{SETTINGS}->{IMAGES_DIR}."/".$self->{ENTRIES}[$n]->{DIRNAME}.".jpg";
    }
    if ($src_image) {
      my $convert_thumb = undef;
      my $convert_image = undef;

      if ($self->{SETTINGS}->{FORCE_IMAGES}) {
        $convert_thumb = 1;
        $convert_image = 1;
$self->debug(5,"    Forced generation of image/thumb (".$src_image.")");
      } else
     {
      if ( ! -f $dest_thumb ) {
        $convert_thumb = 1;
$self->debug(5,"    Generating non-existing thumb (".$src_image.")");
      } 
      if ( ! -f $dest_image ) {
          if ($object_type ne "album") { 
$self->debug(5,"    Generating non-existing image (".$src_image.")");
            $convert_image = 1;
          }
      } 
     }

      if (!$convert_image) {
        if ($noconv && $object_type ne "album") {
          if (timestamp($src_image)>timestamp($dest_image)) {
$self->debug(5,"    Copying existing but out-of-date image (".$src_image.")");
            $convert_image = 1;
          }
        }
        elsif ( $object_type eq "image" && (! $image_cache->match($src_image, basename($dest_image), $image_size,
                                                                  $self->{SETTINGS}->{GAMMA},
                                                                  $self->{SETTINGS}->{UNSHARP},
                                                                  $self->{SETTINGS}->{IMAGE_QUALITY}))) {
$self->debug(5,"    Generating existing but out-of-date image (".$src_image.")");
          $convert_image = 1;
        }
      }
      if (!$convert_thumb) {
        if ( $object_type eq "album" && (! $thumb_cache->match($src_image, basename($dest_thumb), $album_size,
                                                               $self->{SETTINGS}->{GAMMA},
                                                               $self->{SETTINGS}->{UNSHARP},
                                                               $self->{SETTINGS}->{THUMB_QUALITY} ))) {
          $convert_thumb = 1;
$self->debug(5,"    Generating existing but out-of-date image (".$src_image.")");
        }
        if ( $object_type eq "image" && (! $thumb_cache->match($src_image, basename($dest_thumb), $thumb_size,
                                                               $self->{SETTINGS}->{GAMMA},
                                                               $self->{SETTINGS}->{UNSHARP},
                                                               $self->{SETTINGS}->{THUMB_QUALITY} ))) {
          $convert_thumb = 1;
$self->debug(5,"    Generating existing but out-of-date image (".$src_image.")");
        }
      }

      if ($convert_thumb || $convert_image) {
        my $magick = Image::Magick->new();
        if ($convert_thumb || ($convert_image && (!$noconv))) {
          if ((!$convert_image) || $noconv) {
            $magick->set(size=>$image_size);
          }
          $magick->read($src_image);
          if ($self->{SETTINGS}->{GAMMA} && (!$noconv)) {
            $magick->Gamma($self->{SETTINGS}->{GAMMA});
          }
        }

        if ( $object_type eq "image" ) {
          if ($convert_image) {
            if ($noconv) {
              copy($src_image, $dest_image);
            } else {
              $magick->Resize(geometry=>$image_size);
              if ($self->{SETTINGS}->{UNSHARP}) {
                $magick->UnsharpMask(geometry=>$self->{SETTINGS}->{UNSHARP});
              }
              $magick->set(quality=>$self->{SETTINGS}->{IMAGE_QUALITY});
              $magick->write("jpg:".$dest_image);
              $image_cache->update($src_image, basename($dest_image), $image_size,
                                   $self->{SETTINGS}->{GAMMA}, $self->{SETTINGS}->{UNSHARP},
                                   $self->{SETTINGS}->{IMAGE_QUALITY});
            }
          }
          if ($convert_thumb) {
            $magick->Resize(geometry=>$thumb_size);
            if ($self->{SETTINGS}->{UNSHARP}) {
              $magick->UnsharpMask(geometry=>$self->{SETTINGS}->{UNSHARP});
            }
            $magick->set(quality=>$self->{SETTINGS}->{THUMB_QUALITY});
            $magick->write("jpg:".$dest_thumb);
            $thumb_cache->update($src_image, basename($dest_thumb), $thumb_size,
                                 $self->{SETTINGS}->{GAMMA}, $self->{SETTINGS}->{UNSHARP},
                                 $self->{SETTINGS}->{THUMB_QUALITY});
          }
        } elsif ( $object_type eq "album" ) {
          if ($convert_thumb) {
            $magick->Resize(geometry=>$album_size);
            if ($self->{SETTINGS}->{UNSHARP}) {
              $magick->UnsharpMask(geometry=>$self->{SETTINGS}->{UNSHARP});
            }
            $magick->set(quality=>$self->{SETTINGS}->{THUMB_QUALITY});
            $magick->write("jpg:".$dest_thumb);
            $thumb_cache->update($src_image, basename($dest_thumb), $album_size,
                                 $self->{SETTINGS}->{GAMMA}, $self->{SETTINGS}->{UNSHARP},
                                 $self->{SETTINGS}->{THUMB_QUALITY});
          }
        }
      }
    }
  }
  $thumb_cache->write("thumbs/.cache");
  $image_cache->write("images/.cache");

$self->debug(1,"  Generating HTML");
$self->debug(5,"    Generating index.html");

  my $columns = $self->{SETTINGS}->{COLUMNS};
  if ($self->{SETTINGS}->{LOCAL_COLUMNS}) {
    $columns = $self->{SETTINGS}->{LOCAL_COLUMNS};
  }
  if ( $columns eq "auto" ) {
    if ($self->{CONTAINS_ALBUMS}) {
      $columns = 3;
    } else {
      $columns = 4;
    }
  }


  $self->generate_index($columns);

  for my $n (0 .. $self->{N_ENTRIES}-1) {
    if ( $self->{ENTRIES}[$n]->{OBJECT} eq "image" ) {
$self->debug(5,"    Generating html for \"".$self->{ENTRIES}[$n]->{FILENAME}."\"");
      $self->generate_image($n, $columns);
    }
    if ( $self->{ENTRIES}[$n]->{OBJECT} eq "album" ) {
      mkdir $self->{ENTRIES}[$n]->{DIRNAME};
      $self->{ENTRIES}[$n]->generate($directory."/".$self->{ENTRIES}[$n]->{DIRNAME});
      chdir $directory;
    }
  }

}



sub print_parent_links {
  my $self = shift;
  my $level = shift;
  my $last_link = shift;

  if ($self->{PARENT_ALBUM}) {
    $self->{PARENT_ALBUM}->print_parent_links($level + 1, $last_link);
    print ("     ".$self->{SETTINGS}->{TREE_SEPARATOR}."\n");
  }

  if (($level == 0) && ($last_link eq "n")) {
    print "     ".$self->{TITLE}."\n";
  } else {
    print "     <a href=\"";
    for my $n (1 .. $level) {
      print "../";
    }
    print "index.html\">".$self->{TITLE}."</a>\n";
  }
}

sub print_meta_keywords {
  my $self = shift;
  print $self->{TITLE}.",".$self->{DIRNAME}.",";
  if ($self->{PARENT_ALBUM}) {
    $self->{PARENT_ALBUM}->print_meta_keywords();
  }
}

sub print_meta_keywords_tag {
  my $self = shift;
  print ("  <meta name=\"Keywords\" content=\"");
  $self->print_meta_keywords();
  print ($self->{SETTINGS}->{META_KEYWORDS});
  if ($self->{SETTINGS}->{LOCAL_META_KEYWORDS} ne "") {
    print (",".$self->{SETTINGS}->{LOCAL_META_KEYWORDS});
  }
  print ("\">\n");
}

sub style_link {
  my $self = shift;
  my $level = shift;

  if ($self->{PARENT_ALBUM}) {
    $self->{PARENT_ALBUM}->style_link($level."../");
  }
  if ($self->{SETTINGS}->{CSS_FILE}) {
    my $css = $level.basename($self->{SETTINGS}->{CSS_FILE});
    print ("  <link rel=\"stylesheet\" type=\"text/css\" href=\"".$css."\">\n");
  }
  if ($self->{SETTINGS}->{LOCAL_CSS_FILE}) {
    if ($level eq "") {
      my $css = basename($self->{SETTINGS}->{LOCAL_CSS_FILE});
      print ("  <link rel=\"stylesheet\" type=\"text/css\" href=\"".$css."\">\n");
    }
  }
}

sub about_link {
  my $self = shift;
  my $level = shift;

  if ($self->{SETTINGS}->{ABOUT_FILE}) {
    my $about = $level.basename($self->{SETTINGS}->{ABOUT_FILE});
    print ("     <a class=\"about\" href=\"".$about."\">".$self->{SETTINGS}->{LINK_ABOUT}."</a>\n");
    return "y";
  }
  elsif ($self->{PARENT_ALBUM}) {
    return $self->{PARENT_ALBUM}->about_link($level."../");
  }
  return undef;
}

sub rss_link {
  my $self = shift;
  my $level = shift;

  if ($self->{SETTINGS}->{RSS_BASE}) {
    if ($self->{PARENT_ALBUM}) {
      return $self->{PARENT_ALBUM}->rss_link($level."../");
    } else {
      print ("     <a class=\"about\" href=\"".$level.$self->{SETTINGS}->{RSS_FILE}."\">".$self->{SETTINGS}->{LINK_RSS}."</a>\n");
      return "y";
    }
  }
  return undef;
}

sub rss_meta {
  my $self = shift;
  my $level = shift;

  if ($self->{SETTINGS}->{RSS_BASE}) {
    if ($self->{PARENT_ALBUM}) {
      return $self->{PARENT_ALBUM}->rss_meta($level."../");
    } else {
      print ("  <link rel=\"alternate\" type=\"application/rss+xml\" title=\"RSS\" href=\"".$self->{SETTINGS}->{RSS_BASE}."/".$self->{SETTINGS}->{RSS_FILE}."\">\n");
      return "y";
    }
  }
  return undef;
}

sub colspan {
  my $n = shift;   # Static method!
  if ($n > 1) {
    return " colspan=\"".$n."\"";
  } else {
    return "";
  }
}

sub width {
  my $cols = shift;
  if (($cols >= 1) && ($cols <= 20)) {
    return sprintf(" style=\"width: %.1f%%;\"",(100/$cols));
  } elsif (($cols <= -1) && ($cols >= -20)) {
    return sprintf(" style=\"width: %.1f%%;\"",(100-100/(-$cols)));
  } else {
    return "";
  }
}

sub debug {
  my $self = shift;
  my $level = shift;
  my $msg = shift;
  if ($self->{SETTINGS}->{DEBUG_LEVEL} >= $level) {
    print ($self->{INDENT}."".$msg."\n");
  }
}

sub uri_escape {
  return URI::Escape::uri_escape(shift);
}

sub copy {
  my $source = shift;
  my $dest = shift;
  File::Copy::copy($source, $dest);
}

sub compare_and_copy {
  my $source = shift;
  my $dest = shift;
   if (!-f $dest) {
     File::Copy::copy($source, $dest);
   } elsif ( File::Compare::compare($source, $dest) != 0 ) {
    File::Copy::copy($source, $dest);
  }
}

sub copyToCwd {
  my $source = shift;
  compare_and_copy ($source, pwd()."/".basename($source));
}

sub basename {
  return File::Basename::basename(shift);
}

sub pwd {
  return Cwd::cwd();
}

sub timestamp {
  my $filename = shift;
  return File::stat::stat($filename)->mtime;
}

sub update_date_if_newer {
  my $self = shift;
  my $new_date = shift;

  if (!$self->{DATE}) {
    $self->{DATE} = $new_date;
  } elsif ( DateTime->compare($self->{DATE}, $new_date) < 0 ) {
    $self->{DATE} = $new_date;
  }
}


sub push_dates_to_rss {
  my $self = shift;
  my $arr = shift;
  if (!$self->{CONTAINS_ALBUMS}) {
    if ($self->{DATE}) {
      my $copy = $self->{DATE}->clone();
      $copy->{TITLE} = $self->{TITLE};
      $copy->{URL_PATH} = $self->{URL_PATH};
      push @$arr, $copy;
    }
  } else {
    for my $n (0 .. $self->{N_ENTRIES}-1) {
      if ($self->{ENTRIES}[$n]->{OBJECT} eq "album") {
        $self->{ENTRIES}[$n]->push_dates_to_rss(\@$arr);
      }
    }
  }
}




##########################################
package main;


sub generate_rss {
  my $album = shift;
  my $output = shift;
  my $rss_base = $album->{SETTINGS}->{RSS_BASE};

  if ($rss_base) {
    my @array = ();
    $album->push_dates_to_rss(\@array);
    @array = reverse(sort(@array));

    open (RSS, ">".$output);
    print (RSS "<?xml version=\"1.0\" encoding=\"ISO-8859-2\"?>\n");
    print (RSS "<rss version=\"2.0\">\n");
    print (RSS "<channel>\n");
    print (RSS " <title>".$album->{TITLE}."</title>\n");
    print (RSS " <link>".$rss_base."</link>\n");
    print (RSS " <description> </description>\n");
    print (RSS " <language>en</language>\n");
    print (RSS " <copyright>".$album->{FOOTER}."</copyright>\n");
    print (RSS " <lastBuildDate>".$array[0]->strftime("%a, %d %b %Y %H:%M:%S %z")."</lastBuildDate>\n");

    my $n = 15;
    ITEM_LOOP: for my $item (@array) {
      print (RSS " <item>\n");
      print (RSS "  <title>".$item->{TITLE}."</title>\n");
      print (RSS "  <description> </description>\n");
      print (RSS "  <link>".$rss_base."/".$item->{URL_PATH}."</link>\n");
      print (RSS "  <guid>".$rss_base."/".$item->{URL_PATH}."</guid>\n");
      print (RSS "  <pubDate>".$item->strftime("%a, %d %b %Y %H:%M:%S %z")."</pubDate>\n");
      print (RSS " </item>\n");
      $n--; if ($n <=0) { last ITEM_LOOP; }
    }
    print (RSS "</channel>\n");
    print (RSS "</rss>\n");
    close (RSS);
  }

}



if (!$ARGV[0]) {
  print ("\nPlease specify target directory as a parameter.\n\n");
  exit (1);
}


my $target = $ARGV[0];

my $settings = Settings->new();
$settings->{DEBUG_LEVEL} = 5;

my $album = Album->new(Cwd::cwd(), undef, $settings->clone(), 0);
$album->generate($target);

generate_rss($album, $target."rss.xml");
