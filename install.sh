#!/bin/bash
# use set x for verbose debug output. uncomment at top and bottom
set -x
echo "----------We will need to add an SSH key to codespaces until I can figure out a better method----------"
echo "----------What is your full UMN Email? Ex. urweb@umn.edu----------"
read email
# Make ssh dir in home dir
mkdir /home/drupal/.ssh
echo "----------Genterating SSH key pair--------------"
ssh-keygen -t ed25519 -C "$email" -f /home/drupal/.ssh/id_ed25519 -q -N ""
# Change permissions to private
chmod 600 /home/drupal/.ssh/id_ed25519
echo "----------Start the SSH agent in the background--------------"
eval "$(ssh-agent -s)"
# Add your SSH private key to the SSH agent
ssh-add /home/drupal/.ssh/id_ed25519
echo "----------Please go to https://github.umn.edu/settings/ssh/new (CMD click on mac) and paste the key and give a title--------------"
cat ~/.ssh/id_rsa.pub
echo "----------Press Enter when done----------"
read wait1
echo "----------What is the sitename? (folder name)----------"
read sitename
if [ -d "$sitename" ]
	then
		echo "Sitename directory already exists. Site must be installed"
	else
		git clone -b 9.x-prod git@github.umn.edu:drupalplatform/d8-composer.git $sitename
		cd $sitename
		composer install
		cd docroot/sites/
		echo "----------Please paste in the Default Folder git repo code (Code->SSH->Copy) copied from clipboard and hit enter----------"
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
		# mkcert -install
  		# Gen pw
    		PW=date +%s | sha256sum | base64 | head -c 32
  		# Create db
    		mysql -u admin -p $PW -e "CREATE DATABASE drupal;"
		cd ..
fi
echo "----------Do you have a DB? (y/n)----------"
read dba
if [ $dba == 'Yes' ] || [ $dba == 'yes' ] || [ $dba == 'Y' ] || [ $dba == 'y' ]
	then
		cd $sitename
		echo "----------Please drag and drop the db into the new site folder and wait, then hit enter----------"
		read wait2
		# check for the presence of .sql file
		sqlfile=$(find . -maxdepth 1 -name "*.sql" -print -quit)
		
		# check for the presence of .sql.tar.gz file
		sqltarfile=$(find . -maxdepth 1 -name "*.sql.tar.gz" -print -quit)
		
		if [[ -n $sqlfile ]]; then
		  # .sql file found, import it
		  echo "Found .sql file, starting import..."
		  drush sqlc --database='mysql://admin:$PW@localhost/drupal' < $sqlfile

		elif [[ -n $sqltarfile ]]; then
		  # .sql.tar.gz file found, unzip it and import
		  echo "Found .sql.tar.gz file, starting extraction and import..."
		  gunzip -c $sqltarfile > database-extracted.sql
		  drush sqlc --database='mysql://admin:$PW@localhost/drupal' < database-extracted.sql
		else
		  # neither .sql nor .sql.tar.gz file found, print error message
		  echo "Error: No .sql or .sql.tar.gz file found in the directory."
    		  exit 1
		fi
		echo "----------Clearing cache----------"
		drush cr
		echo "----------Uninstalling prod modules----------"
		drush pm-uninstall -y simplesamlphp_auth memcache acquia_purge purge
		cd ..
elif  [ $dba == 'No' ] || [ $dba == 'no' ] || [ $dba == 'N' ] || [ $dba == 'n' ]
	then
 		echo "----------Please enter a password for the site. Username is admin----------"
   		read loginpw
 		drush si lightning_umn --db-url=mysql://admin:$PW@localhost/drupal --site-name='My Drupal Site' --account-name=admin --account-pass=$loginpw
		echo "----------Site install finished!----------"
		read asdf
else
	echo "----------Error with input!----------"
fi
cd $sitename
echo "----------Configure stage proxy? (y/n)----------"
read stageproxy
if [ $stageproxy == 'Yes' ] || [ $stageproxy == 'yes' ] || [ $stageproxy == 'Y' ] || [ $stageproxy == 'y' ]
	then
	drush pm-enable -y stage_file_proxy
	echo "----------Whats the Site name? (eg gradschool-d8 for gradschool-d8.dev.umn.edu)----------"
	read stageurlname
	echo "----------Dev, stg or Prd?----------"
	echo "Dev = [1]"
	echo "Stg = [2]"
	echo "Prod = [3]"
	read devorprd
	if [ $devorprd == 1 ]
		then
		drush cset -y stage_file_proxy.settings origin https://$stageurlname.dev.umn.edu
	elif [ $devorprd == 2 ]
		then
		drush cset -y stage_file_proxy.settings origin https://$stageurlname.stg.umn.edu
	elif [ $devorprd == 3 ]
		then
		drush cset -y stage_file_proxy.settings origin https://$stageurlname.umn.edu
	else
		echo "----------wrong input detected----------"
	fi
	drush cset -y stage_file_proxy.settings verify 0
	drush cset -y stage_file_proxy.settings origin_dir sites/$stageurlname.umn.edu/files
fi
echo "----------Configuring cache settings----------"
drush cset -y system.file path.temporary /tmp
drush -y config-set system.performance css.preprocess 0
drush -y config-set system.performance js.preprocess 0
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
		drush updb
		drush cr
fi
echo "----------Generating login link----------"
drush uli
echo "----------Finished!----------"
set +x
