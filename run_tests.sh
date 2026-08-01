#!/usr/bin/env sh
pass=0
total=0
status=0
for test in tests/*.lua; do
	total=$((total+1))
	if nvim --headless -u NONE -l "$test"; then
		pass=$((pass+1))
		echo "$(tput setaf 2)$test passed$(tput sgr0)"
	else
		status=1
		echo "$(tput setaf 1)$(tput bold)$test failed$(tput sgr0)"
	fi
done

echo "$(tput bold)-> $pass/$total tests passing$(tput sgr0)"
exit $status
