# name: discourse-users-extend
# about: Plugin para mostrar usuarios de Discourse y agruparlos por país.
# version: 0.1
# authors: Héctor Sanchez

after_initialize do
  # Controlador simple sin Engine
  class ::DiscourseUsersController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :check_xhr, only: [:users, :page, :debug]
    skip_before_action :preload_json, only: [:users, :page, :debug]
    skip_before_action :redirect_to_login_if_required, only: [:users, :page, :debug]
    
    def users
      # Establecer headers para respuesta JSON
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      unless SiteSetting.dmu_enabled
        render json: { error: "El plugin de usuarios de Discourse está deshabilitado." }, status: 403
        return
      end

      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      limit = SiteSetting.dmu_discourse_api_limit

      if api_key.blank? || discourse_url.blank?
        render json: { error: "API Key y URL de Discourse no configurados correctamente." }, status: 400
        return
      end

      begin
        require 'net/http'
        require 'uri'
        require 'json'
        
        # Obtener usuarios usando el directorio y luego obtener información completa de cada uno
        all_users = []
        
        # Primero obtener la lista de usuarios del directorio
        uri = URI("#{discourse_url}/directory_items.json")
        uri.query = URI.encode_www_form({
          'period' => 'all',
          'order' => 'created',
          'limit' => limit
        })
        
        request_uri = URI(uri.to_s)
        http = Net::HTTP.new(request_uri.host, request_uri.port)
        http.use_ssl = true if request_uri.scheme == 'https'
        http.read_timeout = 30
        
        request = Net::HTTP::Get.new(request_uri)
        request['Api-Key'] = api_key
        request['Api-Username'] = api_username
        
        response_http = http.request(request)
        
        if response_http.code.to_i == 200
          data = JSON.parse(response_http.body)
          if data['directory_items']
            # Obtener información completa de cada usuario
            data['directory_items'].each do |item|
              user = item['user']
              if user && user['username']
                # Obtener información completa del usuario
                user_uri = URI("#{discourse_url}/users/#{user['username']}.json")
                user_request_uri = URI(user_uri.to_s)
                user_http = Net::HTTP.new(user_request_uri.host, user_request_uri.port)
                user_http.use_ssl = true if user_request_uri.scheme == 'https'
                user_http.read_timeout = 10
                
                user_request = Net::HTTP::Get.new(user_request_uri)
                user_request['Api-Key'] = api_key
                user_request['Api-Username'] = api_username
                
                user_response = user_http.request(user_request)
                
                if user_response.code.to_i == 200
                  user_data = JSON.parse(user_response.body)
                  if user_data['user']
                    all_users << user_data['user']
                  end
                else
                  # Si falla, usar los datos básicos que tenemos
                  all_users << user
                end
              end
            end
          end
        else
          Rails.logger.warn "Error obteniendo usuarios del directorio: #{response_http.code}"
        end
        
        # Si no obtuvimos usuarios de los grupos de confianza, intentar con el endpoint de usuarios
        if all_users.empty?
          # Intentar con el endpoint de usuarios con más detalles
          uri = URI("#{discourse_url}/admin/users/list/active.json")
          uri.query = URI.encode_www_form({
            'limit' => limit,
            'offset' => 0,
            'order' => 'created',
            'asc' => 'true'
          })
          
          request_uri = URI(uri.to_s)
          http = Net::HTTP.new(request_uri.host, request_uri.port)
          http.use_ssl = true if request_uri.scheme == 'https'
          http.read_timeout = 30
          
          request = Net::HTTP::Get.new(request_uri)
          request['Api-Key'] = api_key
          request['Api-Username'] = api_username
          
          response_http = http.request(request)
          
          if response_http.code.to_i == 200
            data = JSON.parse(response_http.body)
            all_users = data if data.is_a?(Array)
          end
        end
        
        # Si aún no tenemos usuarios, intentar con el endpoint de usuarios públicos
        if all_users.empty?
          uri = URI("#{discourse_url}/directory_items.json")
          uri.query = URI.encode_www_form({
            'period' => 'all',
            'order' => 'created',
            'limit' => limit
          })
          
          request_uri = URI(uri.to_s)
          http = Net::HTTP.new(request_uri.host, request_uri.port)
          http.use_ssl = true if request_uri.scheme == 'https'
          http.read_timeout = 30
          
          request = Net::HTTP::Get.new(request_uri)
          request['Api-Key'] = api_key
          request['Api-Username'] = api_username
          
          response_http = http.request(request)
          
          if response_http.code.to_i == 200
            data = JSON.parse(response_http.body)
            if data['directory_items']
              all_users = data['directory_items'].map { |item| item['user'] }.compact
            end
          end
        end
        
        if all_users.empty?
          render json: { error: "No se pudieron obtener usuarios de Discourse" }, status: 500
          return
        end

        # Procesar usuarios y agrupar por país
        processed_users = all_users.map do |user|
          # Extraer país de la ubicación
          location = user['location']
          country = if location.present?
            # Si la ubicación contiene una coma, tomar la parte después de la coma (país)
            if location.include?(',')
              location.split(',').last.strip
            else
              location
            end
          else
            "Sin país"
          end
          
          {
            firstname: user['name']&.split(' ')&.first || user['username'],
            lastname: user['name']&.split(' ')&.drop(1)&.join(' ') || '',
            email: user['email'],
            username: user['username'],
            country: country,
            trust_level: user['trust_level'] || 0,
            avatar_template: user['avatar_template']
          }
        end

        grouped = processed_users.group_by { |u| u[:country] }
        result = grouped.transform_values do |arr|
          arr.map { |u| { 
            firstname: u[:firstname], 
            lastname: u[:lastname], 
            email: u[:email],
            username: u[:username],
            trust_level: u[:trust_level],
            avatar_template: u[:avatar_template]
          } }
        end

        render json: { 
          success: true,
          users_by_country: result, 
          total_users: processed_users.length,
          timestamp: Time.current.iso8601
        }
      rescue JSON::ParserError => e
        Rails.logger.error "Error parsing Discourse API response: #{e.message}"
        render json: { error: "Respuesta inválida de la API de Discourse" }, status: 500
      rescue => e
        Rails.logger.error "Error en Discourse API: #{e.message}"
        render json: { error: "Error al obtener usuarios: #{e.message}" }, status: 500
      end
    end

    def page
      # Renderizar la página HTML
      render html: "<div id='discourse-users-page'></div>".html_safe, layout: 'application'
    end

    def debug
      # Endpoint temporal para debug - ver qué datos devuelve la API
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      # Solo permitir a administradores
      return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      
      if api_key.blank? || discourse_url.blank?
        render json: { error: "API Key y URL de Discourse no configurados correctamente." }, status: 400
        return
      end

      begin
        require 'net/http'
        require 'uri'
        require 'json'
        
        # Probar endpoint de usuario individual (más información de perfil)
        uri = URI("#{discourse_url}/users/jason.nardi.json")
        
        request_uri = URI(uri.to_s)
        http = Net::HTTP.new(request_uri.host, request_uri.port)
        http.use_ssl = true if request_uri.scheme == 'https'
        http.read_timeout = 30
        
        request = Net::HTTP::Get.new(request_uri)
        request['Api-Key'] = api_key
        request['Api-Username'] = api_username
        
        response_http = http.request(request)
        
        debug_data = {
          status_code: response_http.code.to_i,
          headers: response_http.to_hash,
          body: response_http.body
        }
        
        if response_http.code.to_i == 200
          data = JSON.parse(response_http.body)
          debug_data[:parsed_data] = data
          if data['user']
            user_data = data['user']
            debug_data[:sample_user] = user_data
            debug_data[:sample_user_keys] = user_data.keys
          end
        end
        
        render json: debug_data
      rescue => e
        render json: { error: "Error en debug: #{e.message}" }, status: 500
      end
    end

    def save_settings
      return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      SiteSetting.dmu_discourse_api_key = params[:dmu_discourse_api_key]
      SiteSetting.dmu_discourse_api_username = params[:dmu_discourse_api_username]
      SiteSetting.dmu_discourse_api_url = params[:dmu_discourse_api_url]
      SiteSetting.dmu_discourse_api_limit = params[:dmu_discourse_api_limit]
      render json: { success: true }
    end
  end

  # Registrar las rutas directamente
  Discourse::Application.routes.append do
    get '/discourse/users' => 'discourse_users#users'
    get '/discourse-users-page' => 'discourse_users#page'
    get '/discourse/debug' => 'discourse_users#debug'
    post '/discourse/save_settings' => 'discourse_users#save_settings'
  end
end



