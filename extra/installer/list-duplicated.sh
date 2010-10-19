#!/bin/bash

for dir in main extras
do
	echo -n > ${dir}_WITH_VERSIONS
	echo -n > ${dir}_WITHOUT_VERSIONS
	echo -n > REMOVE_${dir}

	for i in `find $dir -name "*.deb"`
	do
		NAME=`echo $i | sed 's/.*\///g' | cut -d'_' -f1`
		VERSION=`dpkg-deb --info $i | grep ^" Version:" | cut -d' ' -f3`
		echo "$NAME $VERSION" >> ${dir}_WITH_VERSIONS
		echo $NAME >> ${dir}_WITHOUT_VERSIONS
	done
done

cat main_WITHOUT_VERSIONS extras_WITHOUT_VERSIONS | sort | uniq -c | cut -c7- | grep -v ^1 | cut -d' ' -f2 > DUPLICATED_PACKAGES

for i in `cat DUPLICATED_PACKAGES`
do
	MAIN_VERSION=`grep $i main_WITH_VERSIONS | cut -d' ' -f2| head -1`
	EXTRA_VERSION=`grep $i extras_WITH_VERSIONS | cut -d' ' -f2 | head -1`
	# FIXME: Probably there is a bug here (false positive with samba)
	if [ $EXTRA_VERSION \> $MAIN_VERSION ]
	then
		# extras version newer than main one but may be unsafe to remove
        # the main one if it is a package belonging to the base system
		echo $i >> REMOVE_main_unsafe
	else
		echo $i >> REMOVE_extras
	fi
done

# be careful with duplicated packages in extras
# the older version has to be removed manually by now
ls extras | cut -d'_' -f1 | uniq -c | grep -v "    1" | cut -d' ' -f8- > NO_REMOVE

cp REMOVE_extras FINAL_REMOVE

for i in `cat NO_REMOVE`
do
    sed -i "/^$i$/d" FINAL_REMOVE
done

for dir in main extras
do
	rm ${dir}_WITH_VERSIONS
	rm ${dir}_WITHOUT_VERSIONS
done
rm DUPLICATED_PACKAGES
