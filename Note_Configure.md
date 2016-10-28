I. FLAT NETWORK
If you want a flat network (you can ping directly to public network)
When you creat network in Admin mode
Choose Creat Network:
1. Name: 
Type:   external_network
2. Project
Choose: admin
3. Provider Network Type 
Choose : Flat
4. Physical Network (just have in Flat mode because Flat will make some bridges to connect with public network)
Type: ext_br-ext 
p/s: You can reference in "nano /etc/neutron/plugins/ml2/ml2_conf.ini"
(Note: just for this script)
5. Choose External Network
And submit

II. Creat a new image of Ubuntu Server
When you chose mode Protected. You can not delete this image.
If you want to delete this image, you must be remove tick mode proteced.
File image:
https://drive.google.com/drive/folders/0B9HAnVcCIQmgaVptMjZZa2NoNlk?usp=sharing
username: ubuntu
password: ubuntu

III. Creat new user in VM
When you create a new instance from image
You need to generate a keypair, name "key.pem".
then ssh or use putty with this key to login
'ssh -i key.pem ubuntu@x.x.x.x'

GOOD LUCK!!!!
