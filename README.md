# Sonnen_ChargeHQ_script
Bash script for fetching data from Sonnen battery to ChargeHQ EV charge app using push-API

##First find the IP-address of your Sonnen battery.
In a webbrowser write: https://find-my.sonnen-batterie.com/ 
Then you will see this and can see your IP address

![image](https://user-images.githubusercontent.com/6228518/215452261-a122d26f-3bcf-47ee-9e24-6f258506d748.png)

##Next log-in to find your Sonnen API key. 


##Getting your ChargeHq API key
Log into https://app.chargehq.net/.
Click settings
Select "My Equipment" -> Solar battery equipment.
Select the "Push Api" item.
Copy your API key into the ChargeHq ApiKey setting.
More details can be found here. https://chargehq.net/kb/push-api.

##After successfully pushing sonnen data to your ChargeHQ app it will look like this:


![Screenshot_20230130_134652_net chargehq app](https://user-images.githubusercontent.com/6228518/215715610-98e0e6c3-e3c8-4804-909d-4c7f17926558.jpg)
