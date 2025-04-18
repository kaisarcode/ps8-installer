# Load environment variables
. ./.env

# Clean up old installation
sudo echo 'Cleaning up...'
mkdir -p www
sudo docker-compose down
sudo chmod -R 777 www
sudo rm -rf www
mkdir -p www

# Download PrestaShop source
major=$(echo "$PSVERSION" | cut -d. -f1)
minor=$(echo "$PSVERSION" | cut -d. -f2)
if [ "$major" -lt 8 ] || [ "$major" -eq 8 -a "$minor" -lt 0 ]; then
    wget "https://download.prestashop.com/download/releases/prestashop_${PSVERSION}.zip"
else
    wget "https://github.com/PrestaShop/PrestaShop/releases/download/${PSVERSION}/prestashop_${PSVERSION}.zip"
fi

# Install base files
unzip prestashop_$PSVERSION.zip -d www
sudo rm prestashop_$PSVERSION.zip
rm www/Install_PrestaShop.html
rm www/index.php
unzip www/prestashop.zip -d www
rm www/prestashop.zip
sudo chmod -R 777 www

# Build environment
sudo docker-compose build
sudo docker-compose up -d

# Check DB is up before continue
echo 'Check DB is up before continuing...'
attempts=0
while [ $attempts -lt 30 ]; do
    if [ "$(sudo docker inspect -f {{.State.Running}} $DBCONTAINER)" = "true" ]; then
        # Additional check for MySQL 8.0
        if sudo docker exec $DBCONTAINER mysqladmin ping -h localhost -u root -p${DBPASS} > /dev/null 2>&1; then
            echo 'DB is up and responding. Continue.'
            break
        fi
    fi
    attempts=$((attempts + 1))
    sleep 1
done
if [ $attempts -eq 30 ]; then
    echo 'Timeout: DB did not become available within the specified time.'
    exit 1
fi

# Complete domain info
if [ $PSPORT != 80 ]; then
    PSDOMAIN="${PSDOMAIN}:${PSPORT}";
fi

# Install PrestaShop
echo 'Setting up PrestaShop, please wait...'
sudo docker exec -ti $PSCONTAINER sh -c \
"php install/index_cli.php \
--db_create=1 \
--db_server=${DBCONTAINER} \
--db_name=${DBNAME} \
--db_password=${DBPASS} \
--db_user=root \
--prefix=${DBPREFIX} \
--domain=${PSDOMAIN} \
--language=${PSLANG} \
--email=${PSEMAIL} \
--password=${PSPASS} \
--name=${PSNAME} \
--send_email=0 \
--newsletter=0"

# Set up admin dir
sudo mv www/admin www/$PSADMINDIR
#sudo rm -rf www/var/cache
sudo rm -rf www/install

# Install geolocation database
cp assets/GeoLite2-City.mmdb www/app/Resources/geoip/GeoLite2-City.mmdb

# Set permissions
sudo chmod -R 777 www
#find www -type d -exec sudo chmod 0755 {} \;
#find www -type f -exec sudo chmod 0644 {} \;

# Done!
echo "Setup finished.";
