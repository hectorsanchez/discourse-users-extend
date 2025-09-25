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
# Pasar parámetro como variable de entorno
BATCHES_TO_PROCESS = ENV['BATCHES_TO_PROCESS'] || 'all'
puts '=== INICIANDO CARGA OPTIMIZADA DE CACHE ==='
puts 'Fecha: ' + Time.current.to_s
puts 'Estrategia: Lotes de 60 usuarios, pausa de 1 minuto entre lotes'
puts ''

# Limpiar cache actual
puts 'Limpiando cache actual...'
\$users_by_country_cache = {}
\$cache_last_updated = nil
\$cache_loading = false

# Configuración optimizada
BATCH_SIZE = 60
BATCH_DELAY = 60  # 1 minuto entre lotes
USER_DELAY = 0.5  # 500ms entre usuarios

# Función para hacer petición individual con reintento
def fetch_user_location_with_retry(username, api_key, api_username, discourse_url, max_retries = 3)
  retries = 0
  
  while retries < max_retries
    begin
      user_url = \"#{discourse_url.chomp('/')}/users/#{username}.json\"
      
      uri = URI(user_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'
      
      request = Net::HTTP::Get.new(uri)
      request['Api-Key'] = api_key
      request['Api-Username'] = api_username
      
      response = http.request(request)
      
      if response.code == '200'
        user_data = JSON.parse(response.body)
        location = user_data['user']&.dig('location') || ''
        puts \"  ✅ #{username}: #{location.empty? ? 'Sin ubicación' : location}\"
        return location
      elsif response.code == '429'
        retries += 1
        wait_time = 30 * retries  # 30s, 60s, 90s
        puts \"  ⚠️ #{username}: Rate limit (429), esperando #{wait_time}s (intento #{retries}/#{max_retries})\"
        sleep(wait_time)
      else
        puts \"  ❌ #{username}: Error #{response.code}\"
        return ''
      end
    rescue => e
      puts \"  ❌ #{username}: Exception #{e.message}\"
      return ''
    end
  end
  
  puts \"  ❌ #{username}: Falló después de #{max_retries} intentos\"
  return ''
end

# Función para extraer solo el país
def extract_country_only(location)
  return 'No country' if location.nil? || location.empty?
  
  normalized = location.downcase.strip
  
  # Mapeo de países
  country_mapping = {
    'athens, greece' => 'Greece',
    'tunis, tunisia' => 'Tunisia',
    'paris, france' => 'France',
    'madrid, spain' => 'Spain',
    'belgrade, serbia' => 'Serbia',
    'tirana, albania' => 'Albania',
    'rabat, morocco' => 'Morocco',
    'luxembourg, luxembourg' => 'Luxembourg',
    'brussels, belgium' => 'Belgium',
    'prague, czech republic' => 'Czech Republic',
    'budapest, hungary' => 'Hungary',
    'london, united kingdom' => 'United Kingdom',
    'new york, united states' => 'United States',
    'buenos aires, argentina' => 'Argentina',
    'nairobi, kenya' => 'Kenya',
    'kampala, uganda' => 'Uganda',
    'cairo, egypt' => 'Egypt'
  }
  
  if country_mapping[normalized]
    return country_mapping[normalized]
  end
  
  parts = normalized.split(', ')
  if parts.length > 1
    return parts.last.capitalize
  end
  
  return 'No country'
end

# Obtener configuración
api_key = SiteSetting.dmu_discourse_api_key
api_username = SiteSetting.dmu_discourse_api_username
discourse_url = SiteSetting.dmu_discourse_api_url

puts \"Configuración API: key_present=#{!api_key.blank?}, username_present=#{!api_username.blank?}, url=#{discourse_url}\"

if api_key.blank? || discourse_url.blank?
  puts 'ERROR: API Key y Discourse URL no configurados correctamente'
  exit 1
end

# Obtener usuarios de grupos
puts 'Obteniendo usuarios de grupos...'
all_users = []

trust_levels = ['trust_level_0', 'trust_level_1', 'trust_level_2', 'trust_level_3', 'trust_level_4']

trust_levels.each do |trust_level|
  puts \"Obteniendo usuarios de: #{trust_level}\"
  
  offset = 0
  limit = 1000
  
  loop do
    groups_url = \"#{discourse_url.chomp('/')}/groups/#{trust_level}/members.json?limit=#{limit}&offset=#{offset}\"
    
    uri = URI(groups_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'
    http.read_timeout = 30
    
    request = Net::HTTP::Get.new(uri)
    request['Api-Key'] = api_key
    request['Api-Username'] = api_username
    
    groups_response = http.request(request)
    
    if groups_response.code.to_i == 200
      groups_data = JSON.parse(groups_response.body)
      users = groups_data['members'] || []
      
      if users.empty?
        puts \"No hay más usuarios para #{trust_level}\"
        break
      end
      
      all_users.concat(users)
      puts \"#{trust_level}: #{users.length} usuarios agregados (total: #{all_users.length})\"
      
      if users.length < limit
        puts \"Fin de usuarios para #{trust_level}\"
        break
      end
      
      offset += limit
    else
      puts \"Error obteniendo usuarios de #{trust_level}: #{groups_response.code}\"
      break
    end
    
    sleep(2.0)
  end
end

# Eliminar duplicados
unique_users = all_users.uniq { |u| u['username'] }
puts \"Usuarios únicos obtenidos: #{unique_users.length}\"

# Procesar usuarios con estrategia optimizada
puts 'Iniciando procesamiento optimizado...'
puts \"Lotes de #{BATCH_SIZE} usuarios\"
puts \"Pausa de #{BATCH_DELAY} segundos entre lotes\"
puts \"Tiempo estimado: #{(unique_users.length / BATCH_SIZE.to_f * BATCH_DELAY / 60).round(1)} minutos\"

user_batches = unique_users.each_slice(BATCH_SIZE).to_a
puts \"Total de lotes disponibles: #{user_batches.length}\"

# Determinar cuántos lotes procesar
if \"#{BATCHES_TO_PROCESS}\" == \"all\"
  batches_to_process = user_batches.length
  puts \"Procesando TODOS los lotes: #{batches_to_process}\"
else
  batches_to_process = \"#{BATCHES_TO_PROCESS}\".to_i
  if batches_to_process > user_batches.length
    batches_to_process = user_batches.length
    puts \"Ajustando a #{batches_to_process} lotes (máximo disponible)\"
  else
    puts \"Procesando #{batches_to_process} lotes de #{user_batches.length} disponibles\"
  end
end

\$users_by_country_cache = {}
processed_count = 0
error_count = 0
countries_found = Set.new

user_batches.first(batches_to_process).each_with_index do |batch, batch_index|
  puts \"\"
  puts \"=== LOTE #{batch_index + 1}/#{batches_to_process} ===\"
  puts \"Procesando #{batch.length} usuarios...\"
  
  batch.each_with_index do |user_data, user_index|
    begin
      username = user_data['username']
      puts \"Usuario #{user_index + 1}/#{batch.length}: #{username}\"
      
      # Hacer petición individual con reintento
      location = fetch_user_location_with_retry(username, api_key, api_username, discourse_url)
      
      if !location.nil?
        # Extraer país
        country = extract_country_only(location)
        
        # Procesar usuario
        name_parts = (user_data['name'] || '').split(' ')
        firstname = name_parts.first || username
        lastname = name_parts.drop(1).join(' ') || ''
        
        processed_user = {
          firstname: firstname,
          lastname: lastname,
          email: user_data['email'],
          username: username,
          location: location,
          country: country,
          trust_level: user_data['trust_level'],
          avatar_template: user_data['avatar_template']
        }
        
        # Agregar al cache
        \$users_by_country_cache[country] ||= []
        \$users_by_country_cache[country] << processed_user
        countries_found.add(country)
        processed_count += 1
      end
      
      # Delay entre usuarios
      sleep(USER_DELAY)
      
    rescue => e
      puts \"Error procesando usuario #{user_data['username']}: #{e.message}\"
      error_count += 1
    end
  end
  
  puts \"Lote #{batch_index + 1} completado. Usuarios procesados: #{processed_count}\"
  puts \"Países encontrados: #{countries_found.size}\"
  
  # Pausa entre lotes (excepto el último)
  if batch_index < batches_to_process - 1
    puts \"Pausa de #{BATCH_DELAY} segundos hasta el siguiente lote...\"
    sleep(BATCH_DELAY)
  end
end

\$cache_last_updated = Time.current

puts \"\"
puts \"=== CARGA OPTIMIZADA COMPLETADA ===\"
puts \"Usuarios procesados: #{processed_count}\"
puts \"Países encontrados: #{countries_found.size}\"
puts \"Errores: #{error_count}\"
puts \"Cache actualizado: #{\$cache_last_updated}\"
puts \"Países: #{countries_found.to_a.sort.join(', ')}\"
puts \"\"
puts \"Usuarios por país:\"
\$users_by_country_cache.each do |country, users|
  puts \"  #{country}: #{users.length} usuarios\"
end

# Guardar cache en disco
cache_file_path = Rails.root.join('tmp', 'discourse_users_cache.json')
cache_data = {
  users_by_country: \$users_by_country_cache,
  cache_updated: \$cache_last_updated,
  cache_loading: false
}

File.write(cache_file_path, JSON.generate(cache_data))
puts \"Cache guardado en disco: #{cache_file_path}\"

puts \"\"
puts \"=== CACHE CARGADO EXITOSAMENTE ===\"
puts \"Fecha de finalización: #{Time.current}\"
"
