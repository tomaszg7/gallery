#!/usr/bin/perl
#
#  skrypt muflona
#  przerobiony tak,ze:
#  1)jesli w katalogu znajduje sie plik about.html to ZAMIAST Prev,Up,Next bedzie About Author
#  2)jesli w katalogu znajduje sie plik nazwa_pliku_graficznego.txt (konczacego sie na txt) to 
#    zawartosc tego pliku zostaje dopisana do stronki z ta konkretna fotka
#  3)uwzglednia zmienna Footer
#  4)zmienione parametry konwersji i rozmiar obrazka
#  5)odwrotna numeracja katalogow. (todo: thumby albumow sa wciaz numerowane normalnie)

use strict;


##########################################
package Cache;

# Tab delimited files:  local_image(w/o path) source_image size
# Stored as two assoc. arrays local_image, containing "source

sub new {
  shift;
  my $filename = shift;

  my $self = {};
  $self->{DATA} = {};
  bless $self;

  if ( -f $filename ) {
    open (my $file, $filename);
    while (<$file>) {
      if (/(.+)\t(.+)\t(.+)/) {
        $self->{DATA}{$1} = $2."\t".$3;
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

  if ( ($self->{DATA}{$local_image} eq $src_image."\t".$image_size) ) {
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

  $self->{DATA}{$local_image} = $src_image."\t".$image_size;
}

sub write {
  my $self = shift;
  my $filename = shift;

  open FILE, ">$filename";
  my $key;
  foreach $key ( keys %{$self->{DATA}} ) {
    print FILE $key."\t".$self->{DATA}{$key}."\n";
  }
  close FILE;
  
}




##########################################
package Settings;

sub new {
  shift;
  my $filename = shift;

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
  $self->{TREE_SEPARATOR} = "&diams;";
  $self->{FOOTER} = "&nbsp;";
  $self->{DISPLAY_EXIF} = "y";
  $self->{FORCE_IMAGES} = undef;
  $self->{DEBUG_LEVEL} = 3;

  $self->{HIGHLIGHT} = "highlight.jpg";
  $self->{CSS_FILE} = undef;
  $self->{LOCAL_CSS_FILE} = undef;
  $self->{IMAGE_SIZE} = "1000x700";
  $self->{LOCAL_IMAGE_SIZE} = undef;
  $self->{THUMB_SIZE} = "210x140";
  $self->{LOCAL_THUMB_SIZE} = undef;
  $self->{CONVERT_OPTIONS} = "-sharpen 3 -quality 90";
  $self->{LOCAL_CONVERT_OPTIONS} = undef;
  $self->{COLUMNS} = 4;
  $self->{LOCAL_COLUMNS} = undef;

  bless $self;

  return $self;
}

sub clone {
  my $self = shift;
  my $clone = { %$self }; 
  $clone->{CSS_FILE} = undef;
  $clone->{LOCAL_CSS_FILE} = undef;
  $clone->{LOCAL_IMAGE_SIZE} = undef;
  $clone->{LOCAL_THUMB_SIZE} = undef;
  $clone->{LOCAL_CONVERT_OPTIONS} = undef;
  $clone->{LOCAL_COLUMNS} = undef;
  bless $clone, ref $self;
}


##########################################
package Image;

sub new {
  shift;

  my $self = {};
  $self->{OBJECT} = "image";
  $self->{FILENAME} = shift;
  $self->{TITLE} = shift;
  $self->{DATE} = undef;
  bless $self;

  open (EXIF, "exif -i \"".$self->{FILENAME}."\"|");
  while (<EXIF>) {
    if (/0x0110\|(.*)/) {
      $self->{CAMERA} = $1;
      $self->{CAMERA} =~ s/\s+$//;
    }
    elsif (/0x0132\|(\d\d\d\d):(\d\d):(\d\d) (\d\d:\d\d)/) {
      $self->{DATE} = $3."-".$2."-".$1;
    }
    elsif (/0x829a\|(\S*)/) {
      $self->{SHUTTER_SPEED} = $1;
    }
    elsif (/0x829d\|(\S*)/) {
      $self->{APERTURE} = $1;
    }
    elsif (/0x8827\|(\S*)/) {
      $self->{ISO} = $1;
    }
    elsif (/0x9202\|(\S*)/) {
      $self->{APERTURE} = $1;
    }
    elsif (/0x920a\|(\S*)/) {
      $self->{FOCAL_LENGTH} = $1;
    }
  }
  close (EXIF);

  if ($self->{CAMERA} && $self->{DATE} && $self->{SHUTTER_SPEED} &&
      $self->{APERTURE} && $self->{ISO} && $self->{FOCAL_LENGTH}) {
    $self->{HAS_EXIF} = "y";
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
  $self->{TITLE} = `basename "$directory"`;
  chomp $self->{TITLE};
  $self->{DATE} = undef;
  $self->{PARENT_ALBUM} = shift;
  $self->{ENTRIES} = ();
  $self->{N_ENTRIES} = 0;
  $self->{N_IMAGES} = 0;
  $self->{SETTINGS} = shift;
  $self->{NEST} = shift;
  bless $self;

  $self->{INDENT} = "";
  for my $n (1 .. $self->{NEST}) {
    $self->{INDENT} = "  ".$self->{INDENT};
  }

  my $pushd = `pwd`; chomp $pushd;
  chdir $directory;

  my $css_basename = undef;
  my $local_css_basename = undef;

$self->debug(1,"Initializing new album in: \"".$directory."\"");
  if (open my $datafile, $self->{SETTINGS}->{DATAFILE}) {
    while (<$datafile>) {
      chomp;
      if (/#(.*)/) {
$self->debug(1,"  Skipping coment:  ".$1);
      }
      elsif (/^TITLE:\s+(.+)/) {
        $self->{TITLE} = $1;
$self->debug(1,"  Read TITLE: \"".$self->{TITLE}."\"");
      }
      elsif (/^DATE:\s+(.+)/) {
        $self->{DATE} = $1;
$self->debug(1,"  Read DATE:  \"".$self->{DATE}."\"");
      }
      elsif (/^BREAK:\s?(.*)/) {
        my $title = $1;
        my $break = Break->new($title);
        push @{$self->{ENTRIES}}, $break;
$self->debug(1,"  Read BREAK: \"".$title."\"");
      }
      elsif (/LOCAL_CSS:\s+(.+)\s*/) {
        $self->{SETTINGS}->{LOCAL_CSS_FILE} = $directory."/".$1;
$self->debug(1,"  Read LOCAL_CSS: \"".$self->{SETTINGS}->{LOCAL_CSS_FILE}."\"");
        $local_css_basename = `basename "$self->{SETTINGS}->{LOCAL_CSS_FILE}"`;
        chomp $local_css_basename;
      }
      elsif (/CSS:\s+(.+)\s*/) {
        $self->{SETTINGS}->{CSS_FILE} = $directory."/".$1;
$self->debug(1,"  Read CSS: \"".$self->{SETTINGS}->{CSS_FILE}."\"");
        $css_basename = `basename "$self->{SETTINGS}->{CSS_FILE}"`;
        chomp $css_basename;
      }
      elsif (/HIGHLIGHT:\s+(.+)\s*/) {
        $self->{SETTINGS}->{HIGHLIGHT} = $1;
        chomp $self->{SETTINGS}->{HIGHLIGHT};
$self->debug(1,"  Read HIGHLIGHT: \"".$self->{SETTINGS}->{HIGHLIGHT}."\"");
      }
      elsif (/LOCAL_COLUMNS:\s+([123456789])\s*/) {
        $self->{SETTINGS}->{LOCAL_COLUMNS} = $1;
$self->debug(1,"  Read LOCAL_COLUMNS: \"".$self->{SETTINGS}->{LOCAL_COLUMNS}."\"");
      }
      elsif (/COLUMNS:\s+([123456789])\s*/) {
        $self->{SETTINGS}->{COLUMNS} = $1;
$self->debug(1,"  Read COLUMNS: \"".$self->{SETTINGS}->{COLUMNS}."\"");
      }
      elsif (/FOOTER:\s+(.+)/) {
        $self->{SETTINGS}->{FOOTER} = $1;
$self->debug(1,"  Read FOOTER: \"".$self->{SETTINGS}->{COLUMNS}."\"");
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
      elsif (/LOCAL_CONVERT_OPTIONS:\s+(\S*)\s*/) {
        $self->{SETTINGS}->{LOCAL_CONVERT_OPTIONS} = $1;
        chomp $self->{SETTINGS}->{LOCAL_CONVERT_OPTIONS};
$self->debug(1,"  Read LOCAL_CONVERT_OPTIONS: \"".$self->{SETTINGS}->{LOCAL_CONVERT_OPTIONS}."\"");
      }
      elsif (/CONVERT_OPTIONS:\s+(\S*)\s*/) {
        $self->{SETTINGS}->{CONVERT_OPTIONS} = $1;
        chomp $self->{SETTINGS}->{CONVERT_OPTIONS};
$self->debug(1,"  Read CONVERT_OPTIONS: \"".$self->{SETTINGS}->{CONVERT_OPTIONS}."\"");
      }
      elsif (/\+(.+)\s*/) {
        my $mask = $1; chomp $mask;
$self->debug(1,"  Including from mask: \"".$mask."\"");
        open (my $list, "ls -d $mask|sort|");
        while (<$list>) {
          my $filename = $_; chomp $filename;
          if ( -d $filename ) {
$self->debug(1,"    Directory: \"".$filename."\"");
            my $album = Album->new($directory."/".$filename, $self, $self->{SETTINGS}->clone(), $self->{NEST}+3);
            push @{$self->{ENTRIES}}, $album;
            if ($filename eq $self->{SETTINGS}->{HIGHLIGHT}) {
              $self->{HIGHLIGHT} = $album->{HIGHLIGHT};
            }
          } elsif ((-f $filename) && ($filename ne $self->{SETTINGS}->{DATAFILE}) && ($filename ne $css_basename) && ($filename ne $local_css_basename) && !($filename =~ /txt$/)) {
$self->debug(5,"    File: \"".$filename."\"");
            my $image = Image->new($directory."/".$filename, undef);
            $image->{IMAGE_INDEX} = $self->{N_IMAGES};
            $self->{N_IMAGES}++;
            push @{$self->{ENTRIES}}, $image;
            if ($filename eq $self->{SETTINGS}->{HIGHLIGHT}) {
              $self->{HIGHLIGHT} = $image;
            }
          }
        }
        close ($list);
      }
      else {
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
          if ($highlight eq "!") {
            $self->{HIGHLIGHT} = $album->{HIGHLIGHT};
          }
        } elsif ((-f $filename) && ($filename ne $self->{SETTINGS}->{DATAFILE}) && ($filename ne $css_basename) && ($filename ne $local_css_basename)) {
          my $image = Image->new($directory."/".$filename, $title);
          $image->{IMAGE_INDEX} = $self->{N_IMAGES};
          $self->{N_IMAGES}++;
          push @{$self->{ENTRIES}}, $image;
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

  my $pushd = `pwd`; chomp $pushd;
  chdir $directory;

  open (my $dir, "ls -d *|sort|");
  while (<$dir>) {
    my $filename = $_; chomp $filename;
    if ( (-d $filename) && ($filename ne ".") && ($filename ne "..")) {
$self->debug(1,"  Adding sub-directory \"".$filename."\"");
      my $album = Album->new($directory."/".$filename, $self, $self->{SETTINGS}->clone(), $self->{NEST}+1);
      push @{$self->{ENTRIES}}, $album;
    }
  }
  close $dir;

  chdir $pushd;
}

sub add_all_files {
  my $self = shift;
  my $directory = shift;

  my $pushd = `pwd`; chomp $pushd;
  chdir $directory;

  open (my $dir, "ls -d *|sort|");
  while (<$dir>) {
    my $filename = $_; chomp $filename;
    if ((-f $filename) && (substr($filename,0,1) ne ".") && !($filename =~ /txt$/)) {
$self->debug(5,"  Adding image \"".$filename."\"");
      my $image = Image->new($directory."/".$filename, undef);
      $image->{IMAGE_INDEX} = $self->{N_IMAGES};
      $self->{N_IMAGES}++;
      push @{$self->{ENTRIES}}, $image;
    }
  }
  close $dir;
  chdir $pushd;
}

sub generate_index {
  my $self = shift;

  open my $oldout, ">&STDOUT";

  my $title = $self->{SETTINGS}->{DEFAULT_ALBUM_TITLE};
  if ($self->{TITLE}) {
    $title = $self->{TITLE};
  }
  my $columns = $self->{SETTINGS}->{COLUMNS};
  if ($self->{SETTINGS}->{LOCAL_COLUMNS}) {
    $columns = $self->{SETTINGS}->{LOCAL_COLUMNS};
  }

  open STDOUT,">index.html";
  print ("<html>\n");
  print (" <head>\n");
  print ("  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=".$self->{SETTINGS}->{CHARSET}."\">\n");
  $self->style_link();
  print ("  <title>".$title."</title>\n");
  print (" </head>\n");
  print (" <body>\n");
  print ("  <table cellspacing=\"0\">\n");
  print ("   <tr>\n");
  print ("    <td".colspan($columns-1)." class=\"title\">".$title."</td>\n");
  print ("    <td class=\"date\">".$self->{DATE}."</td>\n");
  print ("   </tr>\n");
  print ("   <tr>\n");
  print ("    <td".colspan($columns-1)." class=\"parent_links\">\n");
  $self->print_parent_links(0, "n");
  print ("    </td>\n");
  print ("    <td class=\"nav_links\">\n");
  
  if (-f "about.html"){
    print ("     <a href=\"about.html\">About ".$self->{TITLE}."</a>\n");
  }
  else{
  print ("      ".$self->{SETTINGS}->{LINK_PREV}."&nbsp;&nbsp;&nbsp;\n");
  if ($self->{PARENT_ALBUM}) {
    print ("     <a href=\"../index.html\">".$self->{SETTINGS}->{LINK_UP}."</a>\n");
  } else {
    print ("     ".$self->{SETTINGS}->{LINK_UP}."\n");
  }
  print ("      &nbsp;&nbsp;&nbsp;".$self->{SETTINGS}->{LINK_NEXT}."\n");
  }
  
  print ("    </td>\n");
  print ("   </tr>\n");

  my $n = 0;
  my $nn = $self->{N_ENTRIES};
#  print("tomaszg debug nn:".$nn);
  ROWS: while ($n < $self->{N_ENTRIES}) {
    print ("   <tr>\n");
    COLS: for my $col (0 .. $columns-1) {
      if ($self->{ENTRIES}[$n]) {
        if ( $self->{ENTRIES}[$n]->{OBJECT} eq "break" ) {
          if ($col > 0) {
            print ("    <td".colspan($columns - $col)." class=\"thumb_empty\">&nbsp;</td>\n");
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
          print ("    <td class=\"thumb_album\">\n");
          print ("     <a href=\"".($nn-$n)."/index.html\">\n");
          print ("      <img class=\"thumb_album\" src=\"".$self->{SETTINGS}->{THUMBS_DIR}."/".$n.".jpg\">\n");
          if ($self->{ENTRIES}[$n]->{TITLE}) {
            print ("      <br>\n");
            print ("      ".$self->{ENTRIES}[$n]->{TITLE}."\n");
          }
          print ("     </a>\n");
          print ("    </td>\n");
          $n++;
        }
        elsif ( $self->{ENTRIES}[$n]->{OBJECT} eq "image" ) {
          print ("    <td class=\"thumb_image\">\n");
          print ("     <a href=\"".$n.".html\">\n");
          print ("      <img class=\"thumb_image\" src=\"".$self->{SETTINGS}->{THUMBS_DIR}."/".$n.".jpg\">\n");
          if ($self->{ENTRIES}[$n]->{TITLE}) {
            print ("      <br>\n");
            print ("      ".$self->{ENTRIES}[$n]->{TITLE}."\n");
          }
          print ("     </a>\n");
          print ("    </td>\n");
          $n++;
        }
      } elsif ($n >= $self->{N_ENTRIES}) {
        print ("    <td".colspan($columns - $col)." class=\"thumb_empty\">&nbsp;</td>\n");
        last COLS;
      } else {
        print ("    <td class=\"thumb_empty\">&nbsp;</td>\n");
        $n++;
      }
      
    }
    print ("   </tr>\n");
  }
  print ("   <tr>\n");
  for my $col (0 .. $columns-1) {
    printf ("    <td width=\"%d%%\">\n", 100/$columns);
  }
  print ("   </tr>\n");
  print ("   <tr>\n");
  print ("    <td".colspan($columns)." class=\"footer\">\n");
  print ("     ".$self->{SETTINGS}->{FOOTER}."\n");
  print ("    </td>\n");
  print ("   </tr>\n");
  print ("  </table>\n");
    print ("  <br><center><script language=\"javascript\"><!-- \n var ipath=\'labfiz.uwb.edu.pl/~tomaszg/istats5\'\n");
  print ("  document.write(\'<SCR\' + \'IPT LANGUAGE=\"JavaScript\"  SRC=\"http://\'+ ipath +\'/istats.js\"><\/SCR\' + \'IPT>\');\n");
      print ("  //-->\n");
        print ("  </script></center>\n");

  print (" </body>\n");
  print ("</html>\n");
  print "\n";
  close STDOUT;

  open STDOUT, ">&", $oldout;
}


sub generate_image {
  my $self = shift;
  my $n = shift;
  my $image = $self->{ENTRIES}[$n];

  my $date = $self->{DATE};
  if ($image->{DATE}) {
    $date = $image->{DATE};
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
  open STDOUT,">".$n.".html";
  print ("<html>\n");
  print (" <head>\n");
  print ("  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=".$self->{SETTINGS}->{CHARSET}."\">\n");
  $self->style_link();
  print ("  <title>".$title."</title>\n");
  print (" </head>\n");
  print (" <body>\n");
  print ("  <table cellspacing=\"0\">\n");
  print ("   <tr>\n");
  print ("    <td class=\"title\">".$title."</td>\n");
  print ("    <td class=\"date\">".$date."</td>\n");
  print ("   </tr>\n");
  print ("   <tr>\n");
  print ("    <td class=\"parent_links\">\n");
  $self->print_parent_links(0, "y");
  print ("     (".$progress.")\n");
  print ("    </td>\n");
  print ("    <td class=\"nav_links\">\n");
  if ($prev_link >= 0) {
    print ("      <a href=\"".$prev_link.".html\">".$self->{SETTINGS}->{LINK_PREV}."</a>");
  } else {
    print ("      ".$self->{SETTINGS}->{LINK_PREV});
  }
  print ("&nbsp;&nbsp;&nbsp;<a href=\"index.html\">".$self->{SETTINGS}->{LINK_UP}."</a>&nbsp;&nbsp;&nbsp;");
  if ($next_link >= 0) {
    print ("<a href=\"".$next_link.".html\">".$self->{SETTINGS}->{LINK_NEXT}."</a>\n");
  } else {
    print ($self->{SETTINGS}->{LINK_NEXT}."\n");
  } 
  print ("    </td>\n");
  print ("   </tr>\n");



  print ("   <tr>\n");
  print ("    <td class=\"image\" colspan=\"2\">\n");
  print ("     <img class=\"image\" src=\"".$self->{SETTINGS}->{IMAGES_DIR}."/".$n.".jpg\">\n");
  print ("    </td>\n");
  print ("   </tr>\n");
  if ($image->{HAS_EXIF} && $self->{SETTINGS}->{DISPLAY_EXIF}) {
    print ("   <tr>\n");
    print ("    <td class=\"exif\" colspan=\"2\">\n");
    print ("     ".$image->{CAMERA}.", ".$image->{FOCAL_LENGTH}."mm, ".$image->{APERTURE}.", ".$image->{SHUTTER_SPEED}."s, ISO ".$image->{ISO}."\n");
    print ("    </td>\n");
    print ("   </tr>\n");
  
  }
  else
  {
    if (-f $self->{ENTRIES}[$n]->{FILENAME}.".txt") {
        open(FILE, $self->{ENTRIES}[$n]->{FILENAME}.".txt");
	print ("   <tr>\n");
        print ("    <td class=\"exif\" colspan=\"2\">\n");
    
	while (<FILE>) {
        print ("$_\n<br>");
	}
        print ("    </td>\n");
	print ("   </tr>\n");
        close(FILE);
    }
  }

  print ("   <tr>\n");
  print ("    <td colspan=\"2\" class=\"footer\">\n");
  print ("     ".$self->{SETTINGS}->{FOOTER}."\n");
  print ("    </td>\n");
  print ("   </tr>\n");
  print ("  </table>\n");
  print ("  <br><center><script language=\"javascript\"><!-- \n var ipath=\'labfiz.uwb.edu.pl/~tomaszg/istats5\'\n");
  print ("  document.write(\'<SCR\' + \'IPT LANGUAGE=\"JavaScript\" SRC=\"http://\'+ ipath +\'/istats.js\"><\/SCR\' + \'IPT>\');\n");
      print ("  //-->\n");
        print ("  </script></center>\n");
  print (" </body>\n");
  print ("</html>\n");
  close STDOUT;
  open STDOUT, ">&", $oldout;
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
    system "cp \"".$self->{SETTINGS}->{CSS_FILE}."\" .";
  }
  if ($self->{SETTINGS}->{LOCAL_CSS_FILE}) {
$self->debug(1,"    Copying ".$self->{SETTINGS}->{LOCAL_CSS_FILE}."");
    system "cp \"".$self->{SETTINGS}->{LOCAL_CSS_FILE}."\" .";
  }

  my $thumb_size = $self->{SETTINGS}->{THUMB_SIZE};
  my $image_size = $self->{SETTINGS}->{IMAGE_SIZE};
  my $convert_options = $self->{SETTINGS}->{CONVERT_OPTIONS};

  if ($self->{SETTINGS}->{LOCAL_CONVERT_OPTIONS}) {
    $convert_options = $self->{SETTINGS}->{LOCAL_CONVERT_OPTIONS};
  }
  if ($self->{SETTINGS}->{LOCAL_IMAGE_SIZE}) {
    $image_size = $self->{SETTINGS}->{LOCAL_IMAGE_SIZE};
  }
  if ($self->{SETTINGS}->{LOCAL_THUMB_SIZE}) {
    $thumb_size = $self->{SETTINGS}->{LOCAL_THUMB_SIZE};
  }

  my $options_thumb = "-geometry ".$thumb_size." ".$convert_options;
  my $options_image = "-geometry ".$image_size." ".$convert_options;

  my $thumb_cache = Cache->new("thumbs/.cache");
  my $image_cache = Cache->new("images/.cache");

  for my $n (0 .. $self->{N_ENTRIES}-1) {
#    print "\n____gawryl debug____\n $self->{ENTRIES}[$n]->{FILENAME}\n"; sleep 1;
    my $src_image = undef;
    if ($self->{ENTRIES}[$n]->{OBJECT} eq "image") {
      $src_image = $self->{ENTRIES}[$n]->{FILENAME};
    } elsif ($self->{ENTRIES}[$n]->{OBJECT} eq "album") {
      $src_image = $self->{ENTRIES}[$n]->{HIGHLIGHT}->{FILENAME};
    }
#    if ($src_image and (!($src_image =~ /txt$/))) {
    if ($src_image) {
      my $dest_thumb = $self->{SETTINGS}->{THUMBS_DIR}."/".$n.".jpg";
      my $dest_image = $self->{SETTINGS}->{IMAGES_DIR}."/".$n.".jpg";
      my $do_convert = undef;
      if ( !( -f $dest_thumb && -f $dest_image) || $self->{SETTINGS}->{FORCE_IMAGES} ) {
$self->debug(5,"    Converting image (".$src_image.")");
        $do_convert = 1;
      } elsif ( $thumb_cache->match($src_image, $n.".jpg", $thumb_size) && $image_cache->match($src_image, $n.".jpg", $image_size) ) {
$self->debug(5,"    Not converting existing and matching image (".$src_image.")");
      } else {
$self->debug(5,"    Converting existing but out-of-date image (".$src_image.")");
        $do_convert = 1;
      }
      if ($do_convert) {
        system "convert ".$options_thumb." \"".$src_image."\" \"".$dest_thumb."\"";
        system "convert ".$options_image." \"".$src_image."\" \"".$dest_image."\"";
        $thumb_cache->update($src_image, $n.".jpg", $thumb_size);
        $image_cache->update($src_image, $n.".jpg", $image_size);
      }
    }
  }
$thumb_cache->write("thumbs/.cache");
$image_cache->write("images/.cache");

$self->debug(1,"  Generating HTML");
$self->debug(5,"    Generating index.html");
  $self->generate_index();

  for my $n (0 .. $self->{N_ENTRIES}-1) {
    if ( $self->{ENTRIES}[$n]->{OBJECT} eq "image" ) {
$self->debug(5,"    Generating html for \"".$self->{ENTRIES}[$n]->{FILENAME}."\"");
      $self->generate_image($n);
    }
    if ( $self->{ENTRIES}[$n]->{OBJECT} eq "album" ) {
      mkdir $n;
#      $self->debug(1,"tomaszgdebug: ".$self->{N_ENTRIES});
      $self->{ENTRIES}[$n]->generate($directory."/".($self->{N_ENTRIES}-$n));
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

sub style_link {
  my $self = shift;
  my $level = shift;

  if ($self->{PARENT_ALBUM}) {
    $self->{PARENT_ALBUM}->style_link($level."../");
  }
  if ($self->{SETTINGS}->{CSS_FILE}) {
    my $css = $level.`basename "$self->{SETTINGS}->{CSS_FILE}"`;
    chomp $css;
    print ("  <link rel=\"stylesheet\" type=\"text/css\" href=\"".$css."\">\n");
  }
  if ($self->{SETTINGS}->{LOCAL_CSS_FILE}) {
    if ($level eq "") {
      my $css = `basename "$self->{SETTINGS}->{LOCAL_CSS_FILE}"`;
      chomp $css;
      print ("  <link rel=\"stylesheet\" type=\"text/css\" href=\"".$css."\">\n");
    }
  }
}

sub colspan {
  my $n = shift;   # Static method!
  if ($n > 1) {
    return " colspan=\"".$n."\"";
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



##########################################
package main;

my $settings = Settings->new("/mnt/q/Foto/gal/settings");
#$settings->{FORCE_IMAGES} = "y";
$settings->{DEBUG_LEVEL} = 5;
my $album = Album->new("/mnt/q/Foto/gal", undef, $settings->clone(), 0);
$album->generate("/mnt/q/Foto/gal/html2");
