#!/bin/bash


unset LANG

if [ -z "$1" ];then
  echo "
Usage:

     $0 [ -q ] <repository_url>

 where repository_url is a full url of a slackware repository
 (supported http only)

Or:

     $0 [ -q ] <filename>

 where filename is the name of a file containing one or more
 repositories. It can contain also text. The script extract
 urls and check if it is a repository.

   -q  print non-verbose progress
   -v  print more verbose info

 The repository url can use the syntax '{ ... }' to specify
 multiple repository in one row. The script expand it and
 check if the expanded repository exists.

 Example:
  http://slackware.osuosl.org/slackware{,64}-{12.2,15.0,current}/
 will be expanded as
  http://slackware.osuosl.org/slackware-12.2/
  http://slackware.osuosl.org/slackware-15.0/
  http://slackware.osuosl.org/slackware-current/
  http://slackware.osuosl.org/slackware64-12.2/
  http://slackware.osuosl.org/slackware64-15.0/
  http://slackware.osuosl.org/slackware64-current/
 Next, when the script will validate the repositories, it will
 remove slackware64-12.2 that does NOT exists.


 You can use this script to expand all repositories in 
   /usr/doc/slackpkg+-*/repositories.txt
"
exit
fi

V=1
if [ "$1" == "-q" ];then
  V=""
  shift
fi
if [ "$1" == "-v" ];then
  V=2
  shift
fi

if [ -f "$1" ];then
  REPOS=$(cat $1|grep -E -o -e 'http://[^ ]*' -e 'https://[^ ]*')
else
  REPOS=$(echo $*|grep -E -o -e 'http://[^ ]*' -e 'https://[^ ]*')
fi

REPOS=$(eval echo $REPOS|sed -e 's/{//g' -e 's/}//g')

[ $V ]&&echo "Expanded repositories" >&2
[ $V ]&&echo $REPOS|sed 's/ /\n/g' >&2

# Define which version of gnupg to use. We'll prefer 1 since it has fewer
# dependencies, then 2, and if we don't find that we'll blindly set this
# to  and deal with it later.
if which 1 > /dev/null 2> /dev/null ; then
  GPG=gpg1
elif which gpg2 > /dev/null 2> /dev/null ; then
  GPG=gpg2
else
  GPG=gpg
fi

TMP=$(mktemp -d)
cd $TMP

( 
echo
echo "Check repositories"
for R in $REPOS;do
  [ $V ]&&echo
  REPO=${R%/}
  echo -n "Repository: $REPO/  "

  HOST=$(echo $REPO|cut -f3 -d/)
  [ $V ]&&echo -en "\n  Host: $HOST\n  Check IP: "||echo -n .
  if echo $HOST|grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$';then
    IP=$HOST
  else
    IP=$(host $HOST 2>/dev/null|grep 'has address'|head -1|awk '{print $NF}')
  fi
  echo $IP|grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
  if [ $? -ne 0 ];then
    [ $V ]&&echo -e "  unable to resolve\nInvalid repository"|grep --color .||echo " Invalid (unable to resolve address)"|grep --color .
    continue
  fi

  [ $V ]&&echo -en "  $IP\n  Check connection: "||echo -n .
  echo |timeout 10 telnet $IP 80 > telnet.out 2>&1 
  ERR=$?
  if grep -q "Escape character is" telnet.out;then
    [ $V ]&&echo "OK "||echo -n .
  elif grep -q "Connection refused" telnet.out;then
    [ $V ]&&echo -e "  Connection refused\nInvalid repository"|grep --color .||echo " Invalid (connection refused)"|grep --color .
    continue
  elif [ $ERR -eq 124 ];then
    [ $V ]&&echo -e "  Timeout\nInvalid repository"|grep --color .||echo " Invalid (timeout)"|grep --color .
    continue
  else
    [ $V ]&&echo -e "  Failed\nInvalid repository"|grep --color .||echo " Invalid (connection failed)"|grep --color .
    continue
  fi

  SIZE=0
  DATE=""
  MD5=no
  [ $V ]&&echo -en "  CHECKSUMS.md5: "||echo -n .
  curl --location --head $REPO/CHECKSUMS.md5 > CHECKSUMS.md5.R 2>/dev/null
  ERR=$?
  if grep -q "^HTTP.*200" CHECKSUMS.md5.R;then
    [ $V ]&&echo -n "OK "||echo -n .
    if grep -q -i Content-Length: CHECKSUMS.md5.R;then
      [ $V ]&&echo -n "$(grep -i Content-Length: CHECKSUMS.md5.R|tail -1|awk '{print $2}'|sed $'s/\r//') bytes "
    fi
    if grep -q -i Last-Modified: CHECKSUMS.md5.R;then
      [ $V ]&&echo -n "($(grep -i Last-Modified: CHECKSUMS.md5.R|tail -1|cut -f2- -d:|sed $'s/\r//') ) "
      DATE="$(grep -i Last-Modified: CHECKSUMS.md5.R|tail -1|cut -f2- -d:|sed $'s/\r//')"
    fi
    [ $V ]&&echo
    MD5=yes
  elif grep -q "^HTTP.*404" CHECKSUMS.md5.R;then
    [ $V ]&&echo -e "  not present\nInvalid repository"|grep --color .||echo " Invalid (CHECKSUMS.md5 not present)"|grep --color .
    continue
  else
    [ $V ]&&echo -e "  unable to retrieve\nInvalid repository"|grep --color .||echo " Invalid (unable to retrieve CHECKSUMS.md5)"|grep --color .
    continue
  fi

  PACK=no
  [ $V ]&&echo -en "  PACKAGES.TXT: "||echo -n .
  curl --location --head $REPO/PACKAGES.TXT > PACKAGES.TXT.R 2>/dev/null
  ERR=$?
  if grep -q "HTTP.*200" PACKAGES.TXT.R;then
    [ $V ]&&echo -n "OK "||echo -n .
    if grep -q -i Content-Length: PACKAGES.TXT.R;then
      [ $V ]&&echo -n "$(grep -i Content-Length: PACKAGES.TXT.R|tail -1|awk '{print $2}'|sed $'s/\r//') bytes "
      SIZE="$(grep -i Content-Length: PACKAGES.TXT.R|tail -1|awk '{print $2}'|sed $'s/\r//')"
    fi
    if grep -q -i Last-Modified: PACKAGES.TXT.R;then
      [ $V ]&&echo -n "($(grep -i Last-Modified: PACKAGES.TXT.R|tail -1|cut -f2- -d:|sed $'s/\r//') ) "
    fi
    [ $V ]&&echo
    PACK=yes
  elif grep -q "HTTP.*404" PACKAGES.TXT.R;then
    [ $V ]&&echo -e "  not present\nInvalid repository"|grep --color .||echo " Invalid (PACKAGES.TXT not present)"|grep --color .
    continue
  else
    [ $V ]&&echo -e "  unable to retrieve\nInvalid repository"|grep --color .||echo " Invalid (unable to retrieve PACKAGES.TXT)"|grep --color .
    continue
  fi

  [ $V ]&&echo -n "  GPG-KEY: "||echo -n .
  wget -o wget.log --timeout=10 --wait=2 --tries=2 -O GPG-KEY $REPO/GPG-KEY
  ERR=$?
  if [ $ERR -eq 0 ];then
    if [ ! -s GPG-KEY ];then
      [ $V ]&&echo "empty"|grep --color .
      GPGKEYFILE=bad
    elif ! grep -q -- "-----END" GPG-KEY;then
      [ $V ]&&echo "invalid"|grep --color .
      GPGKEYFILE=bad
    else
      ID=$($GPG --list-packets GPG-KEY|grep ":user ID packet:"|head -1|cut -f2 -d'"')
      if [ -z "$ID" ];then
        [ $V ]&&echo "Unable to get UID"|grep --color .
        GPGKEYFILE=yes
      else
        [ $V ]&&echo $ID
        GPGKEYFILE=$ID
      fi
      if [ "$V" == "2" ];then
        ( $GPG --list-packets GPG-KEY
          cat GPG-KEY
        )|sed 's/^/    /'
      fi
    fi
  elif grep -q "404 Not Found" wget.log;then
    [ $V ]&&echo "not present"|grep --color .
    GPGKEYFILE=no
  else
    [ $V ]&&echo "unable to retrieve"|grep --color .
    GPGKEYFILEno
  fi

  if [ "$GPGKEYFILE" = "bad" ];then
    [ $V ]&&echo -e "  invalid GPG key\nInvalid repository"|grep --color .||echo " Invalid (GPG-KEY failure)"|grep --color .
    continue
  fi

  if [ ! $V ];then
    echo -n " OK"
    if [ "GPGKEYFILE" != "yes" ];then
      echo -n " ( GPGKEYFILE $GPG )"
    fi
    echo
  else
    echo "Done"
  fi
  if ! echo $SIZE|grep -q "^[1-9][0-9]*$";then
    SIZE="-"
  fi
  SIZE="$(printf "%8d" $SIZE)"
  if date -d "$DATE" >/dev/null 2>&1;then
    DATE=$(date -d "$DATE" "+%Y/%m/%d %H:%M:%S")
  else
    DATE="-"
  fi



  echo -e "$REPO#$SIZE#$DATE#GPGKEYFILE" >> repositories.tmp


done
echo
echo "========================================================"
) >&2

date
echo
(
echo -e "url#    size#date#gpg" 
echo
cat repositories.tmp|sort
)|LANG=C.utf8 column -t -s '#'

cd
#rm -rf $TMP




