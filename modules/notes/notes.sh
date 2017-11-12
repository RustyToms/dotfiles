#!/bin/sh

# Copyright (c) 2017, Juan Cruz Viotti
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#     # derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

ARGV_COMMAND="$1"
ARGV_NOTE="$2"

set -e
set -u

# -------------------------------------------------
# Settings
# -------------------------------------------------

NOTES_GIT_REPOSITORY="$HOME/.notes"
NOTES_GIT_DIRECTORY="$NOTES_GIT_REPOSITORY/.git"
GIT="git --work-tree=$NOTES_GIT_REPOSITORY --git-dir=$NOTES_GIT_DIRECTORY"
EXTENSION="markdown"

# -------------------------------------------------
# Initialization
# -------------------------------------------------

if [ ! -d "$NOTES_GIT_REPOSITORY" ]; then
  echo "Notes directory doesn't exist. Creating..." 1>&2
  mkdir -p "$NOTES_GIT_REPOSITORY"
fi

if [ ! -d "$NOTES_GIT_DIRECTORY" ]; then
  echo "Notes directory is not a git repository. Initializing..." 1>&2
  $GIT init
fi

# -------------------------------------------------
# Functions
# -------------------------------------------------

notes_get_title () (
  path="$1"
  grep "." "$path" \
    | head -n 1 \
    | tr '[:upper:]' '[:lower:]' \
    | awk '{$1=$1;print}' \
    | sed 's,[ /&\+^%!#@$*()_={}:;<>?.,|],-,g' \
    | sed 's/-\{2,\}/-/g' \
    | sed 's/^-//g'
)

notes_fail () (
  message="$1"
  echo "Aborting. $message" 1>&2
  exit 1
)

notes_file_is_modified () (
  path="$1"
  $GIT status --porcelain | grep "^ M $path" > /dev/null
)

notes_stage () (
  path="$1"
  $GIT add "$path"
)

notes_commit () (
  message="$1"
  $GIT commit -m "notes: $message"
)

notes_resolve_name () (
  name="$1"

  if [ -z "$name" ]; then
    notes_fail "Missing note name"
  fi

  # TODO: Allow auto-completion
  FILENAME="$NOTES_GIT_REPOSITORY/$name.$EXTENSION"
  if [ ! -f "$FILENAME" ]; then
    notes_fail "Invalid note name: $name"
  fi

  echo "$name.$EXTENSION"
)

# -------------------------------------------------
# CLI
# -------------------------------------------------

if [ -z "$ARGV_COMMAND" ]; then
  echo "Usage $0 <COMMAND> [NOTE]" 1>&2
  echo "" 1>&2
  echo "Commands:" 1>&2
  echo "" 1>&2
  echo "  add          create a new note" 1>&2
  echo "  ls           list all notes" 1>&2
  echo "  sync         sync notes repository" 1>&2
  echo "  edit <note>  edit a note" 1>&2
  echo "  rm <note>    remove a note" 1>&2
  exit 1
fi

if [ "$ARGV_COMMAND" = "add" ]; then
  TEMPFILE="$(mktemp -t notes).$EXTENSION"
  "$EDITOR" "$TEMPFILE"
  if [ ! -f "$TEMPFILE" ]; then
    notes_fail "Nothing was written"
  fi

  TITLE="$(notes_get_title "$TEMPFILE")"
  if [ -z "$TITLE" ]; then
    rm "$TEMPFILE"
    notes_fail "This note has no title"
  fi

  FILENAME="$TITLE.$EXTENSION"
  # TODO: Make sure this doesn't replace an 
  # existing note with the same title.
  mv "$TEMPFILE" "$NOTES_GIT_REPOSITORY/$FILENAME"
  notes_stage "$FILENAME"
  notes_commit "add note $TITLE using $EDITOR"
elif [ "$ARGV_COMMAND" = "ls" ]; then
  find "$NOTES_GIT_REPOSITORY" \
    -type f \
    -name "*.$EXTENSION" \
    -exec basename -s ".$EXTENSION" {} \;
elif [ "$ARGV_COMMAND" = "edit" ]; then
  FILENAME="$(notes_resolve_name "$ARGV_NOTE")"
  "$EDITOR" "$NOTES_GIT_REPOSITORY/$FILENAME"

  if notes_file_is_modified "$FILENAME"; then
    notes_stage "$FILENAME"
    notes_commit "change note $FILENAME using $EDITOR"
  fi

  NEWTITLE="$(notes_get_title "$NOTES_GIT_REPOSITORY/$FILENAME")"
  if [ "$NEWTITLE" != "$ARGV_NOTE" ]; then
    NEWFILENAME="$NEWTITLE.$EXTENSION"
    mv "$NOTES_GIT_REPOSITORY/$FILENAME" "$NOTES_GIT_REPOSITORY/$NEWFILENAME"
    notes_stage "$FILENAME" 
    notes_stage "$NEWFILENAME"
    notes_commit "move note $FILENAME to $NEWFILENAME"
  fi
elif [ "$ARGV_COMMAND" = "rm" ]; then
  FILENAME="$(notes_resolve_name "$ARGV_NOTE")"
  rm "$NOTES_GIT_REPOSITORY/$FILENAME"
  notes_stage "$FILENAME"
  notes_commit "remove note $FILENAME"
elif [ "$ARGV_COMMAND" = "sync" ]; then
  REMOTES="$($GIT remote -v)"

  if [ -z "$REMOTES" ]; then
    notes_fail "There are no configured remotes for $NOTES_GIT_REPOSITORY"
  fi

  $GIT pull
  $GIT push
else
  notes_fail "Unknown command: $ARGV_COMMAND"
fi