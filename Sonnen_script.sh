#!/bin/sh

############## Change your settings here ##############
# Charge HQ API Endpoint
	endpoint="https://api.chargehq.net/api/public/push-solar-data"
	ChargeHQ_API='XXXXXXXXXXXXXXXXXXXX'

# Sonnen battery IP and sonnen API
	Sonnen_IP="192.168.0.101:80"
	SonnenAPI='XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'


# Define how long time the script wait to collect data from Sonnen battery when zero-production is reported. The previous non-zero production is used once
# then it waits the specified period and then new values are used (even zero-values) - this is needed during night-time and correct zerro production periods.
# This hack is needed as Sonnen battery from time to time falshly report zero-production which will lead ChargeHQ to stop charging. 
# Usually this error correct itself within two minutes.
# Set this interval in seconds  
	zero_wait=420

# Fetching sonnen-data and sending to ChargeHQ-server, interval in seconds 
	sonnen_wait=30

############## END of settings ######################


############# Fetch sonnen data from battery using unique API-token   ####################
Fetch_sonnen_data () {
	# first remove old data
	sonnen_data=""
	sonnen_data=$(curl -m 5 --header "Auth-Token: $SonnenAPI" http://$Sonnen_IP/api/v2/status)  &> /dev/null
}


########## Check if data from sonnen is obtained - for debug.  ##############
check_sonnen_data () { 
	if [ "$sonnen_data" = "" ];
		then 
		Fetch_error="Sonnen fetch error"
	else 
		Fetch_error="We have new data"
	fi
}



############# extract sonnen data from the JSON-string      ####################

extract_sonnen_data () {
# replace all comments and split the data to one variable on each line using newlines.
		data=$(echo "$sonnen_data" | sed 's|,|\n|g')

# Now grab all text after colon (:) on the line containing the key-variable and save it as a new variable for ChargeHQ integration

		#//Get the timestamp from sonnen - not possible yet so grap Timestamp from computer running the script instead - not strictly needed - so is currently not used
		tsms=$(($(date +%s)*1000))

		#// if solar is present, provide the following field
		production_w=$(echo "$data" | grep Production_W |  cut -d ":" -f2-) 

		#// if a consumption meter is present, the following fields should be set
		net_import_w=$(echo "$data" | grep GridFeedIn_W | cut -d ":" -f2-)
		consumption_w=$(echo "$data" | grep Consumption_W | cut -d ":" -f2-)

		#// if accumulated import/export energy is available, set the following fields - I dont think sonnen has this
		#imported_wh=$(echo "$data" | grep GridFeedIn_W | cut -d ":" -f2-) 
		#exported_wh=$(echo "$data" | grep GridFeedIn_W | cut -d ":" -f2-)

		#// if a battery is present, provide the following fields
		battery_discharge_w=$(echo "$data" | grep Pac_total_W | cut -d ":" -f2-) 
		battery_soc=$(echo "$data" | grep USOC | cut -d ":" -f2-) #ok

		#Is this the correct variable from sonnen describing the size of battery?
		battery_energy_wh=$(echo "$data" | grep RemainingCapacity_Wh | cut -d ":" -f2-)
}



############ Convert extracted data to correct name and units, negative positive values according to ChargeHQ standard ##########
convert_to_chargehq () {
	m_production_kw=$(echo "scale=5;"$production_w"/1000" | bc)                             # change w to kw
        production_kw=$(printf '%.3f\n' $(echo "$m_production_kw" | bc -l))                     # in order to have a zerro before decimals like 0.123

	m_net_import_kw=$(echo "scale=5;"$net_import_w"/-1000" | bc)                            # change w to kw and make chargeHQ happy with the direction of flow
        net_import_kw=$(printf '%.3f\n' $(echo "$m_net_import_kw" | bc -l))                     # in order to have a zerro before decimals like 0.123

	m_consumption_kw=$(echo "scale=5;"$consumption_w"/1000" | bc)                           # change w to kw
        consumption_kw=$(printf '%.3f\n' $(echo "$m_consumption_kw" | bc -l))                   # in order to have a zerro before decimals like 0.123

	#m_imported_kwh=$(echo "scale=5;"$imported_wh"/-1000" | bc)                             # change w to kw and to make chargeHQ happy with the direction of flow
        imported_kwh=$(printf '%.3f\n' $(echo "$m_imported_kwh" | bc -l))                       # in order to have a zerro before decimals like 0.123

	#m_exported_kwh=$(echo "scale=5;"$exported_wh"/1000" | bc)                              # change w to kw
        exported_kwh=$(printf '%.3f\n' $(echo "$m_exported_kwh" | bc -l))                       # in order to have a zerro before decimals like 0.123

	m_battery_discharge_kw=$(echo "scale=5;"$battery_discharge_w"/1000" | bc)               # change w to kw
        battery_discharge_kw=$(printf '%.3f\n' $(echo "$m_battery_discharge_kw" | bc -l))       # in order to have a zerro before decimals like 0.123

	m_battery_energy_kwh=$(echo "scale=5;"$battery_energy_wh"/1000" | bc)                   # change w to kw 
        battery_energy_kwh=$(printf '%.3f\n' $(echo "$m_battery_energy_kwh" | bc -l))           # in order to have a zerro before decimals like 0.123

	m_battery_soc=$(echo "scale=3;"$battery_soc"/100" | bc)                                 # change procent to decimal
        battery_soc=$(printf '%.3f\n' $(echo "$m_battery_soc" | bc -l))                         # in order to have a zerro before decimals like 0.123
}



########## Push JSON payload to ChargeHQ  ###############################
Push_to_charHQ () {

	if [ "$sonnen_data" = "" ]; then
		JSON_payload={\"apiKey\":\ \"$ChargeHQ_API\",\"error\":\ \"'Error in fetching Sonnen data'\"}		# when sonnen_data is empty then we miss new sonnen battery data and there is an error in ChargeHQ
		curl -m 3 -H "Content-Type: application/json" -d "$JSON_payload" "$endpoint"   &> /dev/null 		# Send the data-load to ChargeHQ:
		Waiting_loop	
	fi

	if [ $production_w -ne 0 ]; then										# Active if Sonnen report non-zero-produktion
		JSON_payload={\"apiKey\":\ \"$ChargeHQ_API\",\"siteMeters\":\ {\"net_import_kw\":$net_import_kw,\"consumption_kw\":$consumption_kw,\"production_kw\":$production_kw,\"battery_discharge_kw\":$battery_discharge_kw,\"battery_energy_kwh\":$battery_energy_kwh,\"battery_soc\":$battery_soc}}
		copy_JSON_payload="$JSON_payload"									# Copy latest readings from non-zero production so it can be used later	
		curl -m 3 -H "Content-Type: application/json" -d "$JSON_payload" "$endpoint"   &> /dev/null 		# Send the data-load to ChargeHQ:
		sleep $sonnen_wait
	fi

	
	if [ $production_w = 0 ] || [ "$production_w" = "" ]; then 							# Active if Sonnen report zero-produktion
		if [ "$copy_JSON_payload" = "0" ]; then									# If copy_JSON is 0, then it has been used once and therefore the actual readings are used forward
			JSON_payload={\"apiKey\":\ \"$ChargeHQ_API\",\"siteMeters\":\ {\"net_import_kw\":$net_import_kw,\"consumption_kw\":$consumption_kw,\"production_kw\":$production_kw,\"battery_discharge_kw\":$battery_discharge_kw,\"battery_energy_kwh\":$battery_energy_kwh,\"battery_soc\":$battery_soc}}
			curl -m 3 -H "Content-Type: application/json" -d "$JSON_payload" "$endpoint"   &> /dev/null  	# Send the data-load to ChargeHQ:
		else 
			JSON_payload="$copy_JSON_payload"								# Use latest readings if Sonnen report zero-produktion
			copy_JSON_payload=0										# after being used once copy_JSON is set to zero in order not to be used more than once
			curl -m 3 -H "Content-Type: application/json" -d "$JSON_payload" "$endpoint"   &> /dev/null  	# Send the data-load to ChargeHQ:
		fi
		Waiting_loop
	fi

# Send the data-load to ChargeHQ:
#	curl -m 3 -H "Content-Type: application/json" -d "$JSON_payload" "$endpoint"   &> /dev/null 
}


############ Waiting loop that checks for non-zero production data for a specified time ################### 
Waiting_loop () {
	wait_period=0
	while true; do
		Fetch_sonnen_data
		extract_sonnen_data
	sleep $sonnen_wait         								#  Sleeping for number of sec defined in sonnen_wait variable
		wait_period=$(($wait_period+$sonnen_wait))					#  Timer counting the number of sec used for polling Sonnen battery for data 
    			if [ $wait_period -gt $zero_wait ] || [ $production_w -ne 0 ];then	#  Break the script if production is greater than zero or the cript has been running for the time specified in zero_wait variable
				break
 			else
 		      		sleep $sonnen_wait
			fi
done
}


############ Debug section to show variabeles etc:
list_variable () {
#echo here is the curl-collected sonnen data: $sonnen_data
echo Timestamp_ms: "$tsms"
echo Fetch_error: "$Fetch_error"
echo production W: "$production_w"
echo production kW: "$production_kw"
echo net import W: "$net_import_w"
echo net import kW: "$net_import_kw"
echo consumption w: "$consumption_w"
echo consumption kw: "$consumption_kw"
echo Imported W: "$imported_wh"
echo Imported kwh: "$imported_kwh"
echo eksport Wh: "$exported_wh"
echo eksport kWh: "$exported_kwh"
echo Batteri discharge W: "$battery_discharge_w"
echo Batteri discharge kW: "$battery_discharge_kw"
echo Batteri charge pct: "$battery_soc"
echo amount of energy on battery wh: "$battery_energy_wh"
echo amount of energy on battery kwh: "$battery_energy_kwh"
echo ChargeHQ_API: "$ChargeHQ_API"
echo JSON payload: "$JSON_payload"
echo ChargeHQ URL: "$endpoint"
echo Sonnen battery IP: "$Sonnen_IP"
echo Sonnen API-token: "$SonnenAPI"
echo fetch interval: "$sonnen_wait"
echo m_production kW: "$m_production_kw"
echo m_consumption_kw: "$m_consumption_kw"
echo m_net_import_kw: "$m_net_import_kw"
echo m_battery_discharge_kw: "$m_battery_discharge_kw"
echo m_battery_energy_kwh: "$m_battery_energy_kwh"
echo battery_soc: "$battery_soc"
echo copy of JSON: "$copy_JSON_payload"
echo wait in sec after zero-readings: "$zero_wait"
}


debug () {
		Fetch_sonnen_data
		check_sonnen_data
		if [ "$sonnen_data" = "" ];
		then
			echo Fetch_error: "$Fetch_error"; date
		else
			extract_sonnen_data; date
			convert_to_chargehq
			Push_to_charHQ
			#zero_section
			list_variable
		fi
}

#remove # infront to debug the script
#debug



############ here is the actual section that run the script  ####################### 




repeat () {
	while true; do
			Fetch_sonnen_data
			check_sonnen_data
		if [ "$sonnen_data" = "" ];
			then
				echo Fetch_error: "$Fetch_error"; date 
		else
				extract_sonnen_data
				convert_to_chargehq
				Push_to_charHQ
				#debug
		fi
	wait
done
}

repeat
