#!/bin/bash
# Script para cargar cache de usuarios con estrategia optimizada
# Lotes de 60 usuarios con 1 minuto de pausa entre lotes
# Uso: ./load-users-cache-optimized.sh [número_de_lotes]
# Ejemplo: ./load-users-cache-optimized.sh 3  (procesa solo 3 lotes)
# Sin parámetro: procesa todos los lotes

# Obtener número de lotes a procesar
BATCHES_TO_PROCESS=${1:-"all"}

echo "=== INICIANDO CARGA OPTIMIZADA DE CACHE ==="
echo "Fecha: $(date)"
echo "Estrategia: Lotes de 60 usuarios, pausa de 1 minuto entre lotes"
if [ "$BATCHES_TO_PROCESS" = "all" ]; then
  echo "Lotes a procesar: TODOS"
  echo "Tiempo estimado: ~11 minutos"
else
  echo "Lotes a procesar: $BATCHES_TO_PROCESS"
  echo "Tiempo estimado: ~$((BATCHES_TO_PROCESS * 1)) minutos"
fi
echo ""

cd /var/discourse

# Ejecutar el script de carga optimizada
sudo docker exec -it -e BATCHES_TO_PROCESS="$BATCHES_TO_PROCESS" $(sudo docker ps -q) rails runner "
# Configuración
API_KEY = ENV['DMU_DISCOURSE_API_KEY'] || SiteSetting.dmu_discourse_api_key
API_USERNAME = ENV['DMU_DISCOURSE_API_USERNAME'] || SiteSetting.dmu_discourse_api_username
DISCOURSE_URL = ENV['DMU_DISCOURSE_API_URL'] || SiteSetting.dmu_discourse_api_url

puts '=== CONFIGURACIÓN ==='
puts \"API URL: #{DISCOURSE_URL}\"
puts \"API Key: #{API_KEY.present? ? '[CONFIGURADA]' : '[NO CONFIGURADA]'}\"
puts \"API Username: #{API_USERNAME}\"
puts \"Batches to process: #{ENV['BATCHES_TO_PROCESS']}\"
puts ''

# Función para normalizar países
def extract_country_only(location)
  return 'No country' if location.nil? || location.empty?
  
  # Convert to lowercase
  normalized = location.downcase.strip
  
  # Country mapping (city, country -> country only)
  country_mapping = {
    # Czech Republic normalization
    'czech republic' => 'Czech Republic',
    'czech republic' => 'Czech Republic',
    
    # United Kingdom normalization
    'united kingdom' => 'United Kingdom',
    'united kingdom' => 'United Kingdom',
    
    # Nigeria vs Niger distinction
    'nigeria' => 'Nigeria',
    'niger' => 'Niger',
    
    # Greece
    'athens, greece' => 'Greece',
    'larissa, greece' => 'Greece',
    'thessaloniki, greece' => 'Greece',
    'heraklion, greece' => 'Greece',
    
    # Tunisia
    'tunis, tunisia' => 'Tunisia',
    'bizerte, tunisia' => 'Tunisia',
    'monastir, tunisia' => 'Tunisia',
    'sousse, tunisia' => 'Tunisia',
    'sfax, tunisia' => 'Tunisia',
    'kairouan, tunisia' => 'Tunisia',
    'gabès, tunisia' => 'Tunisia',
    
    # France
    'paris, france' => 'France',
    'montreuil, france' => 'France',
    'marseille, france' => 'France',
    'toulouse, france' => 'France',
    'orléans, france' => 'France',
    
    # Spain
    'madrid, spain' => 'Spain',
    'barcelona, spain' => 'Spain',
    'zaragoza, spain' => 'Spain',
    'sevilla, spain' => 'Spain',
    'valencia, spain' => 'Spain',
    
    # Italy
    'rome, italy' => 'Italy',
    'milan, italy' => 'Italy',
    'naples, italy' => 'Italy',
    'turin, italy' => 'Italy',
    'palermo, italy' => 'Italy',
    
    # Germany
    'berlin, germany' => 'Germany',
    'hamburg, germany' => 'Germany',
    'munich, germany' => 'Germany',
    'cologne, germany' => 'Germany',
    'frankfurt, germany' => 'Germany',
    
    # Portugal
    'lisbon, portugal' => 'Portugal',
    'porto, portugal' => 'Portugal',
    'coimbra, portugal' => 'Portugal',
    
    # Belgium
    'brussels, belgium' => 'Belgium',
    'antwerp, belgium' => 'Belgium',
    'ghent, belgium' => 'Belgium',
    
    # Netherlands
    'amsterdam, netherlands' => 'Netherlands',
    'rotterdam, netherlands' => 'Netherlands',
    'the hague, netherlands' => 'Netherlands',
    
    # Poland
    'warsaw, poland' => 'Poland',
    'krakow, poland' => 'Poland',
    'gdansk, poland' => 'Poland',
    
    # Romania
    'bucharest, romania' => 'Romania',
    'cluj-napoca, romania' => 'Romania',
    
    # Bulgaria
    'sofia, bulgaria' => 'Bulgaria',
    'plovdiv, bulgaria' => 'Bulgaria',
    
    # Croatia
    'zagreb, croatia' => 'Croatia',
    'split, croatia' => 'Croatia',
    
    # Slovenia
    'ljubljana, slovenia' => 'Slovenia',
    
    # Slovakia
    'bratislava, slovakia' => 'Slovakia',
    
    # Hungary
    'budapest, hungary' => 'Hungary',
    
    # Czech Republic
    'prague, czech republic' => 'Czech Republic',
    'brno, czech republic' => 'Czech Republic',
    
    # Austria
    'vienna, austria' => 'Austria',
    'salzburg, austria' => 'Austria',
    
    # Switzerland
    'zurich, switzerland' => 'Switzerland',
    'geneva, switzerland' => 'Switzerland',
    
    # Denmark
    'copenhagen, denmark' => 'Denmark',
    'aarhus, denmark' => 'Denmark',
    
    # Sweden
    'stockholm, sweden' => 'Sweden',
    'gothenburg, sweden' => 'Sweden',
    
    # Norway
    'oslo, norway' => 'Norway',
    'bergen, norway' => 'Norway',
    
    # Finland
    'helsinki, finland' => 'Finland',
    'tampere, finland' => 'Finland',
    
    # Ireland
    'dublin, ireland' => 'Ireland',
    'cork, ireland' => 'Ireland',
    
    # United Kingdom
    'london, united kingdom' => 'United Kingdom',
    'manchester, united kingdom' => 'United Kingdom',
    'birmingham, united kingdom' => 'United Kingdom',
    'liverpool, united kingdom' => 'United Kingdom',
    
    # Morocco
    'rabat, morocco' => 'Morocco',
    'casablanca, morocco' => 'Morocco',
    'marrakech, morocco' => 'Morocco',
    'fes, morocco' => 'Morocco',
    
    # Algeria
    'algiers, algeria' => 'Algeria',
    'oran, algeria' => 'Algeria',
    'constantine, algeria' => 'Algeria',
    
    # Egypt
    'cairo, egypt' => 'Egypt',
    'alexandria, egypt' => 'Egypt',
    
    # Turkey
    'istanbul, turkey' => 'Turkey',
    'ankara, turkey' => 'Turkey',
    'izmir, turkey' => 'Turkey',
    
    # Israel
    'tel aviv, israel' => 'Israel',
    'jerusalem, israel' => 'Israel',
    'haifa, israel' => 'Israel',
    
    # Jordan
    'amman, jordan' => 'Jordan',
    
    # Lebanon
    'beirut, lebanon' => 'Lebanon',
    
    # Palestine
    'ramallah, palestine' => 'Palestine',
    'gaza, palestine' => 'Palestine',
    
    # Syria
    'damascus, syria' => 'Syria',
    'aleppo, syria' => 'Syria',
    
    # Iraq
    'baghdad, iraq' => 'Iraq',
    'basra, iraq' => 'Iraq',
    
    # Iran
    'tehran, iran' => 'Iran',
    'isfahan, iran' => 'Iran',
    
    # Saudi Arabia
    'riyadh, saudi arabia' => 'Saudi Arabia',
    'jeddah, saudi arabia' => 'Saudi Arabia',
    
    # United Arab Emirates
    'dubai, united arab emirates' => 'United Arab Emirates',
    'abu dhabi, united arab emirates' => 'United Arab Emirates',
    
    # India
    'mumbai, india' => 'India',
    'delhi, india' => 'India',
    'bangalore, india' => 'India',
    'chennai, india' => 'India',
    'kolkata, india' => 'India',
    
    # China
    'beijing, china' => 'China',
    'shanghai, china' => 'China',
    'guangzhou, china' => 'China',
    'shenzhen, china' => 'China',
    
    # Japan
    'tokyo, japan' => 'Japan',
    'osaka, japan' => 'Japan',
    'kyoto, japan' => 'Japan',
    
    # South Korea
    'seoul, south korea' => 'South Korea',
    'busan, south korea' => 'South Korea',
    
    # Thailand
    'bangkok, thailand' => 'Thailand',
    'chiang mai, thailand' => 'Thailand',
    
    # Vietnam
    'ho chi minh city, vietnam' => 'Vietnam',
    'hanoi, vietnam' => 'Vietnam',
    
    # Philippines
    'manila, philippines' => 'Philippines',
    'cebu, philippines' => 'Philippines',
    
    # Indonesia
    'jakarta, indonesia' => 'Indonesia',
    'surabaya, indonesia' => 'Indonesia',
    
    # Malaysia
    'kuala lumpur, malaysia' => 'Malaysia',
    'penang, malaysia' => 'Malaysia',
    
    # Singapore
    'singapore, singapore' => 'Singapore',
    
    # Australia
    'sydney, australia' => 'Australia',
    'melbourne, australia' => 'Australia',
    'perth, australia' => 'Australia',
    'brisbane, australia' => 'Australia',
    
    # New Zealand
    'auckland, new zealand' => 'New Zealand',
    'wellington, new zealand' => 'New Zealand',
    
    # Canada
    'toronto, canada' => 'Canada',
    'vancouver, canada' => 'Canada',
    'montreal, canada' => 'Canada',
    'calgary, canada' => 'Canada',
    
    # United States
    'new york, united states' => 'United States',
    'los angeles, united states' => 'United States',
    'chicago, united states' => 'United States',
    'houston, united states' => 'United States',
    'phoenix, united states' => 'United States',
    'philadelphia, united states' => 'United States',
    'san antonio, united states' => 'United States',
    'san diego, united states' => 'United States',
    'dallas, united states' => 'United States',
    'san jose, united states' => 'United States',
    'austin, united states' => 'United States',
    'jacksonville, united states' => 'United States',
    'fort worth, united states' => 'United States',
    'columbus, united states' => 'United States',
    'charlotte, united states' => 'United States',
    'san francisco, united states' => 'United States',
    'indianapolis, united states' => 'United States',
    'seattle, united states' => 'United States',
    'denver, united states' => 'United States',
    'washington, united states' => 'United States',
    'boston, united states' => 'United States',
    'el paso, united states' => 'United States',
    'nashville, united states' => 'United States',
    'detroit, united states' => 'United States',
    'oklahoma city, united states' => 'United States',
    'portland, united states' => 'United States',
    'las vegas, united states' => 'United States',
    'memphis, united states' => 'United States',
    'louisville, united states' => 'United States',
    'baltimore, united states' => 'United States',
    'milwaukee, united states' => 'United States',
    'albuquerque, united states' => 'United States',
    'tucson, united states' => 'United States',
    'fresno, united states' => 'United States',
    'mesa, united states' => 'United States',
    'sacramento, united states' => 'United States',
    'atlanta, united states' => 'United States',
    'kansas city, united states' => 'United States',
    'colorado springs, united states' => 'United States',
    'omaha, united states' => 'United States',
    'raleigh, united states' => 'United States',
    'miami, united states' => 'United States',
    'long beach, united states' => 'United States',
    'virginia beach, united states' => 'United States',
    'oakland, united states' => 'United States',
    'minneapolis, united states' => 'United States',
    'tulsa, united states' => 'United States',
    'arlington, united states' => 'United States',
    'tampa, united states' => 'United States',
    'new orleans, united states' => 'United States',
    
    # Mexico
    'mexico city, mexico' => 'Mexico',
    'guadalajara, mexico' => 'Mexico',
    'monterrey, mexico' => 'Mexico',
    'puebla, mexico' => 'Mexico',
    
    # Brazil
    'são paulo, brazil' => 'Brazil',
    'rio de janeiro, brazil' => 'Brazil',
    'brasília, brazil' => 'Brazil',
    'salvador, brazil' => 'Brazil',
    
    # Argentina
    'buenos aires, argentina' => 'Argentina',
    'córdoba, argentina' => 'Argentina',
    'rosario, argentina' => 'Argentina',
    
    # Chile
    'santiago, chile' => 'Chile',
    'valparaíso, chile' => 'Chile',
    
    # Colombia
    'bogotá, colombia' => 'Colombia',
    'medellín, colombia' => 'Colombia',
    'cali, colombia' => 'Colombia',
    
    # Peru
    'lima, peru' => 'Peru',
    'arequipa, peru' => 'Peru',
    
    # Venezuela
    'caracas, venezuela' => 'Venezuela',
    'maracaibo, venezuela' => 'Venezuela',
    
    # Ecuador
    'quito, ecuador' => 'Ecuador',
    'guayaquil, ecuador' => 'Ecuador',
    
    # Bolivia
    'la paz, bolivia' => 'Bolivia',
    'santa cruz, bolivia' => 'Bolivia',
    
    # Paraguay
    'asunción, paraguay' => 'Paraguay',
    
    # Uruguay
    'montevideo, uruguay' => 'Uruguay',
    
    # South Africa
    'cape town, south africa' => 'South Africa',
    'johannesburg, south africa' => 'South Africa',
    'durban, south africa' => 'South Africa',
    'pretoria, south africa' => 'South Africa',
    
    # Nigeria
    'lagos, nigeria' => 'Nigeria',
    'kano, nigeria' => 'Nigeria',
    'ibadan, nigeria' => 'Nigeria',
    'benin city, nigeria' => 'Nigeria',
    'port harcourt, nigeria' => 'Nigeria',
    
    # Kenya
    'nairobi, kenya' => 'Kenya',
    'mombasa, kenya' => 'Kenya',
    
    # Ethiopia
    'addis ababa, ethiopia' => 'Ethiopia',
    
    # Ghana
    'accra, ghana' => 'Ghana',
    'kumasi, ghana' => 'Ghana',
    
    # Uganda
    'kampala, uganda' => 'Uganda',
    
    # Tanzania
    'dar es salaam, tanzania' => 'Tanzania',
    'dodoma, tanzania' => 'Tanzania',
    
    # Democratic Republic of Congo
    'kinshasa, democratic republic of congo' => 'Democratic Republic of Congo',
    'lubumbashi, democratic republic of congo' => 'Democratic Republic of Congo',
    
    # Senegal
    'dakar, senegal' => 'Senegal',
    'touba, senegal' => 'Senegal',
    
    # Mali
    'bamako, mali' => 'Mali',
    
    # Burkina Faso
    'ouagadougou, burkina faso' => 'Burkina Faso',
    
    # Niger
    'niamey, niger' => 'Niger',
    'zinder, niger' => 'Niger',
    
    # Chad
    'n\'djamena, chad' => 'Chad',
    
    # Cameroon
    'douala, cameroon' => 'Cameroon',
    'yaoundé, cameroon' => 'Cameroon',
    
    # Central African Republic
    'bangui, central african republic' => 'Central African Republic',
    
    # Sudan
    'khartoum, sudan' => 'Sudan',
    'port sudan, sudan' => 'Sudan',
    
    # South Sudan
    'juba, south sudan' => 'South Sudan',
    
    # Eritrea
    'asmara, eritrea' => 'Eritrea',
    
    # Djibouti
    'djibouti, djibouti' => 'Djibouti',
    
    # Somalia
    'mogadishu, somalia' => 'Somalia',
    'hargeisa, somalia' => 'Somalia',
    
    # Rwanda
    'kigali, rwanda' => 'Rwanda',
    
    # Burundi
    'bujumbura, burundi' => 'Burundi',
    
    # Madagascar
    'antananarivo, madagascar' => 'Madagascar',
    'toamasina, madagascar' => 'Madagascar',
    
    # Mauritius
    'port louis, mauritius' => 'Mauritius',
    
    # Seychelles
    'victoria, seychelles' => 'Seychelles',
    
    # Comoros
    'moroni, comoros' => 'Comoros',
    
    # Malawi
    'lilongwe, malawi' => 'Malawi',
    'blantyre, malawi' => 'Malawi',
    
    # Zambia
    'lusaka, zambia' => 'Zambia',
    'kitwe, zambia' => 'Zambia',
    
    # Zimbabwe
    'harare, zimbabwe' => 'Zimbabwe',
    'bulawayo, zimbabwe' => 'Zimbabwe',
    
    # Botswana
    'gaborone, botswana' => 'Botswana',
    'francistown, botswana' => 'Botswana',
    
    # Namibia
    'windhoek, namibia' => 'Namibia',
    'walvis bay, namibia' => 'Namibia',
    
    # Angola
    'luanda, angola' => 'Angola',
    'huambo, angola' => 'Angola',
    
    # Mozambique
    'maputo, mozambique' => 'Mozambique',
    'beira, mozambique' => 'Mozambique',
    
    # Lesotho
    'maseru, lesotho' => 'Lesotho',
    
    # Swaziland
    'mbabane, swaziland' => 'Swaziland',
    
    # Madagascar
    'antananarivo, madagascar' => 'Madagascar',
    'toamasina, madagascar' => 'Madagascar',
    
    # Mauritius
    'port louis, mauritius' => 'Mauritius',
    
    # Seychelles
    'victoria, seychelles' => 'Seychelles',
    
    # Comoros
    'moroni, comoros' => 'Comoros',
    
    # Malawi
    'lilongwe, malawi' => 'Malawi',
    'blantyre, malawi' => 'Malawi',
    
    # Zambia
    'lusaka, zambia' => 'Zambia',
    'kitwe, zambia' => 'Zambia',
    
    # Zimbabwe
    'harare, zimbabwe' => 'Zimbabwe',
    'bulawayo, zimbabwe' => 'Zimbabwe',
    
    # Botswana
    'gaborone, botswana' => 'Botswana',
    'francistown, botswana' => 'Botswana',
    
    # Namibia
    'windhoek, namibia' => 'Namibia',
    'walvis bay, namibia' => 'Namibia',
    
    # Angola
    'luanda, angola' => 'Angola',
    'huambo, angola' => 'Angola',
    
    # Mozambique
    'maputo, mozambique' => 'Mozambique',
    'beira, mozambique' => 'Mozambique',
    
    # Lesotho
    'maseru, lesotho' => 'Lesotho',
    
    # Swaziland
    'mbabane, swaziland' => 'Swaziland'
  }
  
  # Check for exact match in mapping
  return country_mapping[normalized] if country_mapping[normalized]
  
  # Try to extract country from comma-separated location
  if normalized.include?(',')
    parts = normalized.split(',').map(&:strip)
    if parts.length >= 2
      # Try the last part as country
      potential_country = parts.last
      return potential_country.capitalize if potential_country.length > 2
    end
  end
  
  # Try to match known country keywords
  country_keywords = [
    'greece', 'tunisia', 'france', 'spain', 'italy', 'germany', 'portugal', 'belgium', 'netherlands',
    'poland', 'romania', 'bulgaria', 'croatia', 'slovenia', 'slovakia', 'hungary', 'czech republic',
    'austria', 'switzerland', 'denmark', 'sweden', 'norway', 'finland', 'ireland', 'united kingdom',
    'morocco', 'algeria', 'egypt', 'turkey', 'israel', 'jordan', 'lebanon', 'palestine', 'syria',
    'iraq', 'iran', 'saudi arabia', 'united arab emirates', 'india', 'china', 'japan', 'south korea',
    'thailand', 'vietnam', 'philippines', 'indonesia', 'malaysia', 'singapore', 'australia',
    'new zealand', 'canada', 'united states', 'mexico', 'brazil', 'argentina', 'chile', 'colombia',
    'peru', 'venezuela', 'ecuador', 'bolivia', 'paraguay', 'uruguay', 'south africa', 'nigeria',
    'kenya', 'ethiopia', 'ghana', 'uganda', 'tanzania', 'democratic republic of congo', 'senegal',
    'mali', 'burkina faso', 'niger', 'chad', 'cameroon', 'central african republic', 'sudan',
    'south sudan', 'eritrea', 'djibouti', 'somalia', 'rwanda', 'burundi', 'madagascar', 'mauritius',
    'seychelles', 'comoros', 'malawi', 'zambia', 'zimbabwe', 'botswana', 'namibia', 'angola',
    'mozambique', 'lesotho', 'swaziland'
  ]
  
  country_keywords.each do |keyword|
    if normalized.include?(keyword)
      return keyword.split(' ').map(&:capitalize).join(' ')
    end
  end
  
  # If no country found, return the original location capitalized
  return location.strip.capitalize
end

# Función para hacer requests con retry
def fetch_user_location_with_retry(username, max_retries = 3)
  retries = 0
  
  while retries < max_retries
    begin
      user_url = \"#{DISCOURSE_URL.chomp('/')}/users/#{username}.json\"
      response = make_api_request(user_url, API_KEY, API_USERNAME)
      
      if response && response['user']
        location = response['user']['location']
        return location
      else
        puts \"  ❌ No user data for #{username}\"
        return nil
      end
      
    rescue => e
      retries += 1
      if e.message.include?('429') || e.message.include?('Too Many Requests')
        delay = [30, 60, 90][retries - 1]
        puts \"  ⏳ Rate limited, waiting #{delay}s (attempt #{retries}/#{max_retries})\"
        sleep(delay)
      else
        puts \"  ❌ Error fetching #{username}: #{e.message}\"
        return nil
      end
    end
  end
  
  puts \"  ❌ Failed to fetch #{username} after #{max_retries} attempts\"
  return nil
end

# Función para hacer requests a la API
def make_api_request(url, api_key, api_username)
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true if uri.scheme == 'https'
  http.read_timeout = 30
  http.open_timeout = 30
  
  request = Net::HTTP::Get.new(uri)
  request['Api-Key'] = api_key
  request['Api-Username'] = api_username
  
  response = http.request(request)
  
  if response.code == '200'
    JSON.parse(response.body)
  else
    raise \"HTTP #{response.code}: #{response.body}\"
  end
end

# Variables globales para el cache
users_by_country = {}
cache_loading = true

puts '=== INICIANDO CARGA DE USUARIOS POR GRUPOS ==='

# Iterar por todos los trust levels
trust_levels = [0, 1, 2, 3, 4]
total_users_processed = 0
total_users_with_location = 0

trust_levels.each do |trust_level|
  puts \"\\n--- Procesando Trust Level #{trust_level} ---\"
  
  offset = 0
  limit = 1000
  batch_number = 0
  
  loop do
    batch_number += 1
    puts \"  Lote #{batch_number} (offset: #{offset})\"
    
    begin
      # URL para obtener miembros del grupo
      group_url = \"#{DISCOURSE_URL.chomp('/')}/groups/trust_level_#{trust_level}/members.json?limit=#{limit}&offset=#{offset}\"
      
      response = make_api_request(group_url, API_KEY, API_USERNAME)
      
      if response && response['members'] && response['members'].any?
        members = response['members']
        puts \"    ✅ Obtenidos #{members.length} miembros\"
        
        # Procesar usuarios en lotes de 60
        user_batches = members.each_slice(60).to_a
        batches_to_process = ENV['BATCHES_TO_PROCESS'] == 'all' ? user_batches.length : ENV['BATCHES_TO_PROCESS'].to_i
        
        puts \"    📦 Procesando #{[batches_to_process, user_batches.length].min} lotes de usuarios\"
        
        user_batches.first(batches_to_process).each_with_index do |user_batch, batch_index|
          puts \"      Lote de usuarios #{batch_index + 1}/#{[batches_to_process, user_batches.length].min}\"
          
          user_batch.each_with_index do |member, user_index|
            username = member['username']
            total_users_processed += 1
            
            print \"        #{user_index + 1}/#{user_batch.length}: #{username}\"
            
            # Obtener location del usuario
            location = fetch_user_location_with_retry(username)
            
            if location && !location.empty?
              total_users_with_location += 1
              country = extract_country_only(location)
              
              # Agregar usuario al cache
              users_by_country[country] ||= []
              users_by_country[country] << {
                'username' => username,
                'name' => member['name'],
                'location' => location,
                'country' => country,
                'trust_level' => trust_level,
                'avatar_template' => member['avatar_template']
              }
              
              print \" -> #{country}\"
            else
              print \" -> No location\"
            end
            
            puts
            
            # Pausa entre usuarios (0.5s)
            sleep(0.5)
          end
          
          # Pausa entre lotes de usuarios (1 minuto)
          if batch_index < user_batches.length - 1
            puts \"      ⏳ Pausa de 1 minuto entre lotes...\"
            sleep(60)
          end
        end
        
        offset += limit
      else
        puts \"    ❌ No hay más miembros en este trust level\"
        break
      end
      
    rescue => e
      puts \"    ❌ Error procesando trust level #{trust_level}: #{e.message}\"
      break
    end
  end
  
  puts \"  📊 Trust Level #{trust_level} completado\"
  puts \"    Total usuarios procesados: #{total_users_processed}\"
  puts \"    Usuarios con location: #{total_users_with_location}\"
end

puts \"\\n=== CARGA COMPLETADA ===\"
puts \"Total usuarios procesados: #{total_users_processed}\"
puts \"Total usuarios con location: #{total_users_with_location}\"
puts \"Países encontrados: #{users_by_country.keys.length}\"

# Mostrar distribución por países
puts \"\\n=== DISTRIBUCIÓN POR PAÍSES ===\"
users_by_country.sort_by { |country, users| users.length }.reverse.each do |country, users|
  puts \"#{country}: #{users.length} usuarios\"
end

# Guardar cache en archivo
cache_file = '/var/www/discourse/tmp/discourse_users_cache.json'
File.write(cache_file, users_by_country.to_json)
puts \"\\n✅ Cache guardado en: #{cache_file}\"

cache_loading = false
puts \"\\n🎉 Proceso completado exitosamente!\"
"