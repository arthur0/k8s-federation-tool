#!/usr/bin/env bash

print_red() {
  printf '%b' "\033[31m$1\033[0m\n"
}

print_green() {
  printf '%b' "\033[32m$1\033[0m\n"
}

clean_screen() {
  printf "\033c"
}

is_linux64(){
  architecture=`uname -p`
  os=`uname`
  result=1 #false
  if  [ "${architecture}" == "x86_64" ] && [ "${os}" == "Linux" ] ; then
    result=0 #true
  fi
  return ${result}
}
