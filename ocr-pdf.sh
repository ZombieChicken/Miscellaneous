#!/bin/bash

# Copyright 2018 ZombieChicken

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# ocr-pdf.sh
#
# The simple purpose of this script is to generate a list of unique "words"
# (words here is very poorly defined and accepts more possibilies than it
# probably should) and store them in a file. The idea is to automatically
# index a PDF to make it easier to find PDFs containing specific content.

# TODO 0001: Perhaps check the filename at the top of the file for a match,
#            and if not, either try and figure out what is going on, or ask
#            the user what to do.
#            Maybe the best option is to print the names of the files and
#            ask the user if this file was renamed, and if they answer yes,
#            skip the file, if no, find the other possible file (perhaps
#            search for the possible collision in the filesystem to see if
#            it even exist anymore?), and if unknown, process the new file
#            and save it's output to another temp file, and if it matches
#            with the current file, either replace the file with the newly
#            generated one, or maintain the older file.
# TODO 0002: Perhaps we should maintain a header so the user can keep track
#            of the possible filenames associated with the output of this
#            script.

# Since we need to make sure all of the binaries we use are available to us,
# we have a function to check to see if they exist in $PATH, and if so, is
# it executable? We check these seperately so that we can be sure why
# we are unable to use the specificed binary.
#
# Arguements: $1 is the binary we are testing for.

check_exist()
{
    PROGRAM=$(which $1 2>/dev/null)
    if [[ $? == "0" ]]
    then
	if [[ "$PROGRAM" == ""  ]]
	then
	    echo "$1 can not be executed"
	    CONTINUE=1
	fi
    else
	echo "$1 can not be found using 'which'"
	CONTINUE=1
    fi
}

# There are many programs that run in this script; all seem to exit with an
# exit status of 0 on success, so this shall be a general solution that we
# can call once we run a command to make sure it exits properly.
#
# Arguements: $1 is the name of the program
#             $2 is the exit status we want this script to exit with
#
# Just to make things easier, each invocation of this function should use a
# different $2 so that, if a command fails and the user has grabbed the exit
# status, they should be able to check and see where the program exited.

exited_correctly()
{
    if [[ $? != '0' ]]
    then
	echo "$1 failed with exit status $?. Exiting script with exit status $2"
	exit $2
    fi
}

# Now that we have our two helper functions set aside, we make sure we have our
# one arguement and start doing some work.

if [[ $1 ]]
then
    # If CONTINUE is a value other than 0, this script will exit, but we will
    # wait until after it has checked for all the needed binaries so we can
    # provide the most info in a single pass and possibly save the user some
    # time trying to fix that which is broken.

    CONTINUE=0

    # Here we check for the binaries we need in no particular order by simply
    # looping over the list and passing them through to check_exist().

    for i in gs tesseract awk sha512sum mktemp basename find
    do
	check_exist $i
    done

    # If CONTINUE isn't still equal to 0, then we're likely missing something above,
    # so we exit here with a status of 1.

    if [[ $CONTINUE != "0" ]]
    then
	exit 1
    fi

    # Here we take $1 (our one arguement) and break it apart into the directory
    # part and the basename/filename. We'll use these later on for find.
    
    DIRECTORY=$(dirname "$1")
    exited_correctly "dirname" 2
    
    FILEGLOB=$(basename "$1")
    exited_correctly "basename" 3

    # Find all the files that match the aforementioned and declared variables
    # so we can start working on everything.
    
    for i in $(find "$DIRECTORY" -name "$FILEGLOB" -print 2>/dev/null)
    do
	# First, since this has to work over PDFs, we need to make sure that
	# is what we're being passed. We'll check what the file is and its
	# mime-type, then assuming the type is application/pdf, we'll continue
	# otherwise we just need to print an error and go on to the next file.

	file --mime-type $i | grep -q "application/pdf"
	
	if [[ $? == "0" ]]
	then
	    
	    # Here we generate the SHA512 sum of the file and use that to name
	    # the output file.

	    SHA512SUM=$(sha512sum $i | cut -d' ' -f1)
	    END_PLAINTEXT_FILE=$SHA512SUM.txt

	    # Assuming END_PLAINTEXT_FILE doesn't exist (if it does, we probably
	    # have done this before), go ahead and process the file. Otherwise,
	    # just emit a message to that effect and go on to the next file, if
	    # one exist.
	    
	    if [[ ! -e $END_PLAINTEXT_FILE ]]
	    then
		TEMP_FILE=$(mktemp -p .)
		exited_correctly "mktemp" 4

		# Insert the name of the file we're processing. While we're
		# using a hash for the filename itself, knowing the old
		# filename might be useful. If the filename at the head of
		# the file doesn't match the SHA512SUM, we know that either
		# there is a file collision or the PDF was renamed.

		echo "AssociatedFile:$i" > $END_PLAINTEXT_FILE
		exited_correctly "echo" 5

		# It is nice to know how many pages we're about to process, so
		# we'll grab that and emit that when we mention the file we're
		# processing and the starting time.
		
		PAGES=$(gs -q -dNODISPLAY -c "($i) (r) file runpdfbegin pdfpagecount = quit")
		exited_correctly "gs" 6
		echo "Converting $i with $PAGES pages, starting at $(date +%H:%M:%S)"

		# Start with the actual conversion, using ghostscript to do the
		# work. Output to the SHA512SUM with a 4 digit, 0 padded number.
		# We use 600 DPI PNG files because they seem to work quite well.
		# 500 might work just as well, but this does quite well with 600.
		
		gs -q -dNOPAUSE -dBATCH -sDEVICE=png16m -r600 -sOutputFile=$SHA512SUM-%04d.png $i
		exited_correctly "gs" 7

		# Loop over the resulting PNG files, running tesseract over each
		# file in turn. We output to TEMP_FILE since we still have some
		# processing to do once this is done.
		
		for v in $(find ./ -name "$SHA512SUM-????.png" -print 2>/dev/null)
		do
		    tesseract -l eng $v - >> $TEMP_FILE
		    exited_correctly "tesseract" 8
		done

		# Now that we have all the plaintext (assuming gs and tesseract
		# havn't messed something up), we'll output one 'word' per line
		# here, convert it to lowercase, sort the output, and remove
		# duplicate entries before outputting the resulting list of
		# words to END_PLAINTEXT_FILE.
		
		awk 'BEGIN{RS=" "} 1' $TEMP_FILE | tr '[:upper:]' '{:lower:]' | sort | uniq >> $END_PLAINTEXT_FILE
		exited_correctly "awk line" 9

		# Now we need to cleanup after ourselves and remove all the
		# (possibly hundreds of) temporary PNG files and plaintext.
		
		rm $TEMP_FILE
		rm $SHA512SUM-????.png

		# Now tell the user we're done and give a timestamp. Timestamp
		# might be useful so we know how long it takes to do (and maybe
		# with the number of pages we printed earlier, the user might
		# get an idea on how long they will need to finish).
		
		echo "Completed $i at $(date +%H:%M:%S)"
	    else
		
		# Apparently our filename is already being used, so print
		# something so the user knows and continue processing.
		
		echo "$i has apparently already been processed, or there is a hash collision"
	    fi
	else
	    echo "$i is not a PDF. Continuing"
	fi
    done
else
    echo "This script requires a single arguement."
    exit 100
fi
