# name: discourse-users-extend
# about: Plugin to display Discourse users and group them by country.
# version: 0.1
# authors: Héctor Sanchez

after_initialize do
  # Cache global para usuarios por país
  $users_by_country_cache = {}
  $cache_last_updated = nil
  $cache_loading = false

  # Controlador simple sin Engine
  class ::DiscourseUsersController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :check_xhr, only: [:index, :users, :debug]
    skip_before_action :preload_json, only: [:index, :users, :debug]
    skip_before_action :redirect_to_login_if_required, only: [:index, :users, :debug]
    
    def index
      # Get list of countries available from cache
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      Rails.logger.info "DISCOURSE USERS: Index request received"
      Rails.logger.info "Cache status before load: empty=#{$users_by_country_cache.empty?}, last_updated=#{$cache_last_updated}"
      
      # Load cache from disk if empty
      if $users_by_country_cache.empty?
        load_cache_from_disk
      end
      
      # Load cache if empty or old
      cache_available = load_cache_if_needed
      
      if cache_available
        # Get countries from cache
        countries = $users_by_country_cache.keys.reject { |c| c == "No country" }.sort
        
        Rails.logger.info "DISCOURSE USERS: Returning #{countries.length} countries: #{countries.join(', ')}"
        
        render json: { 
          success: true, 
          countries: countries,
          total_countries: countries.length,
          cache_updated: $cache_last_updated,
          timestamp: Time.current.iso8601
        }
      else
        # Cache not available
        Rails.logger.warn "DISCOURSE USERS: Cache not available, returning error"
        
        render json: { 
          success: false, 
          error: "Cache not available. Please run the cache generation script manually.",
          message: "To generate cache, run: sudo ./load-users-cache-optimized.sh all",
          countries: [],
          total_countries: 0,
          cache_updated: nil,
          timestamp: Time.current.iso8601
        }
      end
    end
    
    def users
      # Get users for a specific country from cache
      country = params[:country]
      
      Rails.logger.info "DISCOURSE USERS: Users request for country: '#{country}'"
      
      if country.blank?
        Rails.logger.warn "DISCOURSE USERS: Country parameter is blank"
        render json: { error: "Country parameter is required" }, status: 400
        return
      end
      
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      # Load cache from disk if empty
      if $users_by_country_cache.empty?
        load_cache_from_disk
      end
      
      # Load cache if empty or old
      cache_available = load_cache_if_needed
      
      if cache_available
        # Get users from cache
        users = $users_by_country_cache[country] || []
        
        Rails.logger.info "DISCOURSE USERS: Returning #{users.length} users for country '#{country}'"
        
        render json: { 
          success: true, 
          users: users,
          country: country,
          total_users: users.length,
          cache_updated: $cache_last_updated,
          timestamp: Time.current.iso8601
        }
      else
        # Cache not available
        Rails.logger.warn "DISCOURSE USERS: Cache not available, returning error"
        
        render json: { 
          success: false, 
          error: "Cache not available. Please run the cache generation script manually.",
          message: "To generate cache, run: sudo ./load-users-cache-optimized.sh all",
          users: [],
          country: country,
          total_users: 0,
          cache_updated: nil,
          timestamp: Time.current.iso8601
        }
      end
    end

    def save_settings
      return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      SiteSetting.dmu_discourse_api_key = params[:dmu_discourse_api_key]
      SiteSetting.dmu_discourse_api_username = params[:dmu_discourse_api_username]
      SiteSetting.dmu_discourse_api_url = params[:dmu_discourse_api_url]
      render json: { success: true }
    end

    def update_cache
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      Rails.logger.info "DISCOURSE USERS: Update cache endpoint accessed"
      
      # Verificar autenticación
      unless current_user&.admin?
        Rails.logger.warn "DISCOURSE USERS: Unauthorized cache update attempt by #{current_user&.username || 'anonymous'}"
        return render json: { error: "Unauthorized" }, status: 401
      end
      
      Rails.logger.info "DISCOURSE USERS: Manual cache update requested by admin #{current_user.username}"
      
      # Verificar si ya está cargando
      if $cache_loading
        Rails.logger.warn "DISCOURSE USERS: Cache update already in progress, skipping"
        return render json: { 
          success: false, 
          message: "Cache update already in progress",
          timestamp: Time.current.iso8601
        }
      end
      
      # Limpiar cache actual
      Rails.logger.info "DISCOURSE USERS: Clearing existing cache"
      $users_by_country_cache = {}
      $cache_last_updated = nil
      $cache_loading = false
      
      # Iniciar actualización en background
      Rails.logger.info "DISCOURSE USERS: Starting background thread for cache update"
      Thread.new do
        begin
          Rails.logger.info "DISCOURSE USERS: Background cache update thread started"
          load_users_cache
          Rails.logger.info "DISCOURSE USERS: Background cache update completed successfully"
        rescue => e
          Rails.logger.error "DISCOURSE USERS: Background cache update failed: #{e.message}"
          Rails.logger.error "DISCOURSE USERS: Backtrace: #{e.backtrace.first(5).join("\n")}"
        ensure
          $cache_loading = false
          Rails.logger.info "DISCOURSE USERS: Background thread completed, cache_loading set to false"
        end
      end
      
      Rails.logger.info "DISCOURSE USERS: Cache update initiated, returning response"
      render json: { 
        success: true, 
        message: "Cache update started in background. This may take 3-4 minutes.",
        timestamp: Time.current.iso8601,
        estimated_completion: (Time.current + 4.minutes).iso8601,
        cache_status: {
          loading: $cache_loading,
          last_updated: $cache_last_updated,
          countries_count: $users_by_country_cache.keys.length
        }
      }
    end

    def debug
      # Endpoint de diagnóstico simplificado
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      Rails.logger.info "DISCOURSE USERS DEBUG: Starting simple analysis"

      begin
        # Información básica del cache actual
        cache_info = {
          cache_empty: $users_by_country_cache.empty?,
          cache_updated: $cache_last_updated,
          cache_loading: $cache_loading,
          countries_in_cache: $users_by_country_cache.keys.length,
          total_users_in_cache: $users_by_country_cache.values.flatten.length
        }
        
        # Información de configuración
        config_info = {
          api_key_present: !SiteSetting.dmu_discourse_api_key.blank?,
          api_username_present: !SiteSetting.dmu_discourse_api_username.blank?,
          api_url: SiteSetting.dmu_discourse_api_url
        }
        
        # Distribución por países
        country_distribution = {}
        $users_by_country_cache.each do |country, users|
          country_distribution[country] = users.length
        end
        
        # Debug: Show sample data from groups endpoint
        sample_groups_data = nil
        if !$users_by_country_cache.empty?
          sample_user = $users_by_country_cache.values.flatten.first
          sample_groups_data = {
            sample_user: sample_user,
            available_fields: sample_user.keys
          }
        end
        
        render json: {
          success: true,
          timestamp: Time.current.iso8601,
          cache_info: cache_info,
          config_info: config_info,
          country_distribution: country_distribution,
          sample_data: sample_groups_data,
          message: "Debug endpoint working - check cache status and configuration"
        }
        
      rescue => e
        Rails.logger.error "DISCOURSE USERS DEBUG ERROR: #{e.message}"
        render json: { 
          error: "Debug failed: #{e.message}",
          backtrace: e.backtrace.first(5)
        }, status: 500
                  end
                end
                
    private
    
    def cache_file_path
      Rails.root.join('tmp', 'discourse_users_cache.json')
    end
    
    def save_cache_to_disk
      begin
        cache_data = {
          users_by_country: $users_by_country_cache,
          cache_updated: $cache_last_updated,
          cache_loading: $cache_loading
        }
        
        File.write(cache_file_path, JSON.generate(cache_data))
        Rails.logger.info "DISCOURSE USERS: Cache saved to disk at #{cache_file_path}"
      rescue => e
        Rails.logger.error "DISCOURSE USERS: Error saving cache to disk: #{e.message}"
      end
    end
    
    def load_cache_from_disk
      begin
        if File.exist?(cache_file_path)
          cache_data = JSON.parse(File.read(cache_file_path))
          
          $users_by_country_cache = cache_data['users_by_country'] || {}
          $cache_last_updated = cache_data['cache_updated'] ? Time.parse(cache_data['cache_updated']) : nil
          $cache_loading = cache_data['cache_loading'] || false
          
          Rails.logger.info "DISCOURSE USERS: Cache loaded from disk - #{$users_by_country_cache.keys.length} countries, #{$users_by_country_cache.values.flatten.length} users"
        else
          Rails.logger.info "DISCOURSE USERS: No cache file found at #{cache_file_path}"
        end
      rescue => e
        Rails.logger.error "DISCOURSE USERS: Error loading cache from disk: #{e.message}"
      end
    end
    
    def load_cache_if_needed
      # Only load cache if completely empty (not if old)
      cache_empty = $users_by_country_cache.empty?
      cache_loading = $cache_loading
      
      Rails.logger.info "DISCOURSE USERS: Cache check - empty=#{cache_empty}, loading=#{cache_loading}"
      
      if cache_empty
        Rails.logger.warn "DISCOURSE USERS: Cache is empty - no automatic generation"
        Rails.logger.warn "DISCOURSE USERS: Please run the cache generation script manually"
        return false  # Indicate cache is not available
      elsif cache_loading
        Rails.logger.info "DISCOURSE USERS: Cache is already loading, skipping"
        return false
      else
        Rails.logger.info "DISCOURSE USERS: Cache exists, no loading needed"
        return true  # Cache is available
      end
    end

    def load_users_cache
      Rails.logger.info "=== DISCOURSE USERS CACHE - STARTING OPTIMIZED LOAD ==="
      
      begin
        api_key = SiteSetting.dmu_discourse_api_key
        api_username = SiteSetting.dmu_discourse_api_username
        discourse_url = SiteSetting.dmu_discourse_api_url
        
        Rails.logger.info "API Configuration: key_present=#{!api_key.blank?}, username_present=#{!api_username.blank?}, url=#{discourse_url}"
        
        if api_key.blank? || discourse_url.blank?
          Rails.logger.error "DISCOURSE USERS CACHE ERROR: API Key and Discourse URL not configured properly"
          return
        end

        # Use groups endpoint to get ALL users (more complete)
        all_users = []
        
        # Get users from trust level groups (covers all users)
        trust_levels = ['trust_level_0', 'trust_level_1', 'trust_level_2', 'trust_level_3', 'trust_level_4']
        
        trust_levels.each do |trust_level|
          Rails.logger.info "Fetching users from trust level: #{trust_level}"
          
          # Use pagination to get all users from this trust level
          offset = 0
          limit = 1000
          
          loop do
            # Fix URL construction to avoid double slash
            groups_url = "#{discourse_url.chomp('/')}/groups/#{trust_level}/members.json?limit=#{limit}&offset=#{offset}"
            Rails.logger.info "Fetching from: #{groups_url}"
            
            require 'net/http'
            require 'uri'
            require 'json'
            
            uri = URI(groups_url)
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true if uri.scheme == 'https'
            http.read_timeout = 30
            
            request = Net::HTTP::Get.new(uri)
            request['Api-Key'] = api_key
            request['Api-Username'] = api_username
            
            groups_response = http.request(request)
            Rails.logger.info "Trust level #{trust_level} request completed, status: #{groups_response.code}"
            
            if groups_response.code.to_i == 200
              groups_data = JSON.parse(groups_response.body)
              users = groups_data['members'] || []
              
              if users.empty?
                Rails.logger.info "No more users for trust level #{trust_level}, breaking loop"
                break
              end
              
              all_users.concat(users)
              Rails.logger.info "Trust level #{trust_level}: #{users.length} users added (total so far: #{all_users.length})"
              
              # If we got less than the limit, we've reached the end
              if users.length < limit
                Rails.logger.info "Reached end of users for trust level #{trust_level}"
                break
              end
              
              offset += limit
              
            else
              Rails.logger.warn "Failed to get users for trust level #{trust_level}: #{groups_response.code} - #{groups_response.body[0..200]}"
              break
            end
            
            sleep(2.0) # Increased delay for mass processing to avoid rate limiting
          end
          
          Rails.logger.info "Completed trust level #{trust_level}"
        end
        
        # Remove duplicates based on username
        unique_users = all_users.uniq { |u| u['username'] }
        Rails.logger.info "Groups fetch complete: #{all_users.length} total users, #{unique_users.length} unique users"
        
        # Process users with optimized strategy: batches of 60 with 1-minute delays
        Rails.logger.info "Starting optimized processing: batches of 60 users with 1-minute delays"
        
        # Configuration
        batch_size = 60
        batch_delay = 60  # 1 minute between batches
        user_delay = 0.5  # 500ms between users
        
        # Split users into batches
        user_batches = unique_users.each_slice(batch_size).to_a
        Rails.logger.info "Total batches: #{user_batches.length}, estimated time: #{(user_batches.length * batch_delay / 60).round(1)} minutes"
        
        $users_by_country_cache = {}
        processed_count = 0
        error_count = 0
        countries_found = Set.new
        
        # Process each batch
        user_batches.each_with_index do |batch, batch_index|
          Rails.logger.info "=== BATCH #{batch_index + 1}/#{user_batches.length} ==="
          Rails.logger.info "Processing #{batch.length} users..."
          
          batch.each_with_index do |user_data, user_index|
            begin
              username = user_data['username']
              Rails.logger.info "User #{user_index + 1}/#{batch.length}: #{username}"
              
              # Make individual API call to get location
              location = fetch_user_location(username, api_key, api_username, discourse_url)
              
              if !location.nil?  # Only process if no error
                # Extract country from location
                country = extract_country_only(location)
                
                # Process user
                name_parts = (user_data['name'] || "").split(' ')
                firstname = name_parts.first || username
                lastname = name_parts.drop(1).join(' ') || ""
                
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
                
                # Add to cache
                $users_by_country_cache[country] ||= []
                $users_by_country_cache[country] << processed_user
                countries_found.add(country)
                processed_count += 1
              end
              
              # Delay between users
              sleep(user_delay)
              
            rescue => e
              Rails.logger.error "Error processing user #{user_data['username']}: #{e.message}"
              error_count += 1
            end
          end
          
          Rails.logger.info "Batch #{batch_index + 1} completed. Users processed: #{processed_count}"
          Rails.logger.info "Countries found: #{countries_found.size}"
          
          # Pause between batches (except the last one)
          if batch_index < user_batches.length - 1
            Rails.logger.info "Pause of #{batch_delay} seconds until next batch..."
            sleep(batch_delay)
          end
        end
        
        $cache_last_updated = Time.current
        Rails.logger.info "=== OPTIMIZED CACHE LOAD COMPLETE ==="
        Rails.logger.info "Cache loaded successfully:"
        Rails.logger.info "  - Countries found: #{countries_found.size} (#{countries_found.to_a.sort.join(', ')})"
        Rails.logger.info "  - Users processed: #{processed_count}"
        Rails.logger.info "  - Errors encountered: #{error_count}"
        Rails.logger.info "  - Cache timestamp: #{$cache_last_updated}"
        
        # Guardar cache en disco
        save_cache_to_disk
        
      rescue => e
        Rails.logger.error "=== CACHE LOAD ERROR ==="
        Rails.logger.error "Error: #{e.message}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      end
    end

    def fetch_user_location(username, api_key, api_username, discourse_url)
      begin
        user_url = "#{discourse_url.chomp('/')}/users/#{username}.json"
        
        uri = URI(user_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        
        request = Net::HTTP::Get.new(uri)
        request['Api-Key'] = api_key
        request['Api-Username'] = api_username
        
        response = http.request(request)
        
        if response.code == '200'
          user_data = JSON.parse(response.body)
          location = user_data['user']&.dig('location') || ""
          Rails.logger.info "  ✅ #{username}: #{location.empty? ? 'Sin ubicación' : location}"
          return location
        else
          Rails.logger.warn "  ❌ #{username}: Error #{response.code}"
          return ""
        end
      rescue => e
        Rails.logger.warn "  ❌ #{username}: Exception #{e.message}"
        return ""
      end
    end

    def extract_country_only(location)
      return "No country" if location.nil? || location.empty?
      
      # Normalizar espacios alrededor de comas y convertir a minúsculas
      normalized = location.downcase.strip.gsub(/\s*,\s*/, ', ')
      
        # Country mapping (city, country -> country only)
        country_mapping = {
          # Czech Republic normalization
          'czech republic' => 'Czech Republic',
          
          # United Kingdom normalization
          'united kingdom' => 'United Kingdom',
          
          # South Africa normalization
          'south africa' => 'South Africa',
          
          # Nigeria y Niger son el mismo país
          'nigeria' => 'Niger',
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
        'roma, italy' => 'Italy',
        'firenze, italy' => 'Italy',
        'florence, italy' => 'Italy',
        'torino, italy' => 'Italy',
        'palermo, italy' => 'Italy',
        'bologna, italy' => 'Italy',
        'catania, italy' => 'Italy',
        
        # Serbia
        'belgrade, serbia' => 'Serbia',
        'beograd, serbia' => 'Serbia',
        'novi sad, serbia' => 'Serbia',
        'niš, serbia' => 'Serbia',
        
        # Albania
        'tirana, albania' => 'Albania',
        'shkoder, albania' => 'Albania',
        'shkodra, albania' => 'Albania',
        'elbasan, albania' => 'Albania',
        'kruje, albania' => 'Albania',
        
        # Morocco
        'rabat, morocco' => 'Morocco',
        'casablanca, morocco' => 'Morocco',
        'tanger, morocco' => 'Morocco',
        'tangier, morocco' => 'Morocco',
        'agadir, morocco' => 'Morocco',
        
        # Luxembourg
        'luxembourg, luxembourg' => 'Luxembourg',
        'esch-sur-alzette, luxembourg' => 'Luxembourg',
        
        # Belgium
        'brussels, belgium' => 'Belgium',
        'brussel, belgium' => 'Belgium',
        'bruxelles, belgium' => 'Belgium',
        
        # Czech Republic
        'prague, czech republic' => 'Czech Republic',
        'praha, czech republic' => 'Czech Republic',
        'pardubice, czech republic' => 'Czech Republic',
        'brno, czech republic' => 'Czech Republic',
        
        # Hungary
        'budapest, hungary' => 'Hungary',
        'veszprém, hungary' => 'Hungary',
        'pécs, hungary' => 'Hungary',
        
        # Others
        'london, united kingdom' => 'United Kingdom',
        'new york, united states' => 'United States',
        'buenos aires, argentina' => 'Argentina',
        'nairobi, kenya' => 'Kenya',
        'kampala, uganda' => 'Uganda',
        'cairo, egypt' => 'Egypt'
      }
      
      # Look for mapping
      if country_mapping[normalized]
        return country_mapping[normalized]
      end
      
      # If no mapping, try to extract country from the last part
      parts = normalized.split(', ')
      if parts.length > 1
        country = parts.last
        # Capitalizar correctamente países compuestos
        if country.include?(' ')
          return country.split(' ').map(&:capitalize).join(' ')
        else
          return country.capitalize
        end
      end
      
      return "No country"
    end

    
  end

  # Registrar las rutas
  Discourse::Application.routes.append do
    get '/discourse/users' => 'discourse_users#index'  # Get list of countries
    get '/discourse/users/debug' => 'discourse_users#debug'  # Debug endpoint for analysis (MUST be before :country)
    get '/discourse/users/:country' => 'discourse_users#users'  # Get users by country
    post '/discourse/save_settings' => 'discourse_users#save_settings'
    post '/discourse/users/update_cache' => 'discourse_users#update_cache'  # Manual cache update
  end
end