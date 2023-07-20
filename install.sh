#!/bin/bash
# use set x for verbose debug output. uncomment at top and bottom
set -x
echo "----------We will need to add an SSH key to codespaces unti I can figure out a better method----------"
echo "----------What is your full UMN Email? Ex. urweb@umn.edu----------"
read email
echo "----------Genterating SSH key pair--------------"
ssh-keygen -t ed25519 -C "$email" -f /home/codespace/.ssh/id_ed25519 -q -N ""
echo "----------Start the SSH agent in the background--------------"
eval "$(ssh-agent -s)"
# Add your SSH private key to the SSH agent
ssh-add /home/codespace/.ssh/id_ed25519
# install xclip
sudo apt-get install -y xclip
# Copy the contents of the id_ed25519.pub file to your clipboard
xclip -sel clip < /home/codespace/.ssh/id_ed25519.pub
echo "----------Key has been copied to clipboard!--------------"
echo "----------Please go to https://github.umn.edu/settings/ssh/new (CMD click on mac) and paste the key--------------"
echo "----------What is the sitename? (folder name)----------"
read sitename
if [ -d "$sitename" ]
	then
		echo "Sitename directory already exists. Site must be installed"
	else
		git clone -b 9.x-prod git@github.umn.edu:drupalplatform/d8-composer.git $sitename
		cd $sitename
		ddev config --project-type=php
		ddev start
		ddev composer install
		cd docroot/sites/
		echo "----------Please paste in the default git repo code copied from clipboard----------"
		read gitrepo
		if [ -d "default" ]
			then
				rm -rf default/
		fi
		git clone $gitrepo default
		if [ -d "default/files" ]
			then
				mkdir default/files/sync
			else
				mkdir default/files
				mkdir default/files/sync
		fi
		cd ..
		cd ..
		mkcert -install
		ddev config --project-type=drupal9
		ddev restart
		cd ..
fi
echo "----------Do you have a DB? (y/n)----------"
read dba
if [ $dba == 'Yes' ] || [ $dba == 'yes' ] || [ $dba == 'Y' ] || [ $dba == 'y' ]
	then
		cd $sitename
		echo "----------Please drag and drop the db here, then hit enter----------"
		read dbpath
		ddev import-db --src=$dbpath
		echo "----------Clearing cache----------"
		ddev exec drush cr
		echo "----------Uninstalling prod modules----------"
		ddev exec drush pm-uninstall -y simplesamlphp_auth memcache acquia_purge purge
		cd ..
elif  [ $dba == 'No' ] || [ $dba == 'no' ] || [ $dba == 'N' ] || [ $dba == 'n' ]
	then
		echo "----------Please go to site URL above and Install. Hit enter when ready----------"
		read asdf
else
	echo "----------Error with input!----------"
fi
cd $sitename
echo "----------Configure stage proxy? (y/n)----------"
read stageproxy
if [ $stageproxy == 'Yes' ] || [ $stageproxy == 'yes' ] || [ $stageproxy == 'Y' ] || [ $stageproxy == 'y' ]
	then
	ddev exec drush pm-enable -y stage_file_proxy
	echo "----------Whats the Site name? (eg gradschool-d8 for gradschool-d8.dev.umn.edu)----------"
	read stageurlname
	echo "----------Dev, stg or Prd?----------"
	echo "Dev = [1]"
	echo "Stg = [2]"
	echo "Prod = [3]"
	read devorprd
	if [ $devorprd == 1 ]
		then
		ddev exec drush cset -y stage_file_proxy.settings origin https://$stageurlname.dev.umn.edu
	elif [ $devorprd == 2 ]
		then
		ddev exec drush cset -y stage_file_proxy.settings origin https://$stageurlname.stg.umn.edu
	elif [ $devorprd == 3 ]
		then
		ddev exec drush cset -y stage_file_proxy.settings origin https://$stageurlname.umn.edu
	else
		echo "----------wrong input detected----------"
	fi
	ddev exec drush cset -y stage_file_proxy.settings verify 0
	ddev exec drush cset -y stage_file_proxy.settings origin_dir sites/$stageurlname.umn.edu/files
fi
echo "----------Configuring cache settings----------"
ddev exec drush cset -y system.file path.temporary /tmp
ddev exec drush -y config-set system.performance css.preprocess 0
ddev exec drush -y config-set system.performance js.preprocess 0
echo "Overwriting your-site/docroot/sites/development.services.yml"
cat <<EOF > docroot/sites/development.services.yml

parameters:
  http.response.debug_cacheability_headers: true
  twig.config:
    debug: true
    auto_reload: true
    cache: false
services:
  cache.backend.null:
    class: Drupal\Core\Cache\NullBackendFactory

EOF
echo "Appending your-site/docroot/sites/default/settings.php"
cat <<EOF > docroot/sites/default/settings.php

\$settings['container_yamls'][] = DRUPAL_ROOT . '/sites/development.services.yml';
\$settings['cache']['bins']['render'] = 'cache.backend.null';
\$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';

EOF
echo "----------Run db updates? (y/n)----------"
read dba
if [ $dba == 'Yes' ] || [ $dba == 'yes' ] || [ $dba == 'Y' ] || [ $dba == 'y' ]
	then
		ddev exec drush updb
		ddev exec drush cr
fi
ddev restart
echo "----------Generating login link----------"
ddev exec drush uli
echo "----------Finished!----------"
set +x
