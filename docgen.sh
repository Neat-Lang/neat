#!/bin/sh
find doc/sphinx/std/ -name \*.rst |xargs rm
find src/std/ -name \*.nt |\
xargs -P 8 -I {} sh -c 'neat "$0" -c -docgen doc/sphinx/' {}
summary() {
	cat <<-EOT
		.. _std:
		.. highlight:: d

		Standard Library
		=================

		.. toctree::
		   :maxdepth: 2
		   :caption: Contents:
		   :glob:

		   std/**
EOT
	find src/std/ -name \*.nt |sort |\
	while read file
	do
		subfile=$(echo "$file" |sed -e 's,^src/,,' -e 's/.nt$//')
		mod=$(echo "$subfile" |sed -e 's,/,.,g')
		if [ -f doc/sphinx/"$subfile".rst ]
		then
			echo
			echo ".. rubric:: $mod"
			echo
			echo ".. c:namespace:: $mod"
			echo
			grep "Module entries" doc/sphinx/"$subfile".rst
		fi
	done
}
summary > doc/sphinx/std.rst
