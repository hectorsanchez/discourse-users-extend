import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "discourse-users-sidebar",
  initialize() {
    withPluginApi("0.8.31", api => {
      // Agregar enlace al sidebar
      //api.addCommunitySectionLink({
      //  name: "discourse-users",
      //  route: "discovery.latest",
      //  title: "Ver usuarios de Discourse agrupados por país",
      //  text: "Discourse Users",
      //  icon: "users"
      //});

      // Interceptar el click en el enlace del sidebar
      api.onPageChange(() => {
        // Solo procesar si estamos en las páginas específicas
        const currentPath = window.location.pathname;
        const isDiscourseUsersPage = currentPath === "/discourse/users";
        
        if (isDiscourseUsersPage) {
          showDiscourseUsersInterface();
        } else {
          // Si no estamos en las páginas de usuarios, asegurar que la interfaz esté oculta
          hideDiscourseUsersInterface();
        }
      });
    });
  }
};

function showDiscourseUsersInterface() {
  // Verificar si ya existe la interfaz
  if (document.querySelector('.discourse-users-interface')) {
    return;
  }

  // Ocultar el contenido principal de Discourse
  const mainOutlet = document.getElementById('main-outlet');
  if (mainOutlet) {
    mainOutlet.style.display = 'none';
  }

  // Crear la interfaz con CSS inline
  const discourseInterface = document.createElement('div');
  discourseInterface.className = 'discourse-users-interface';
  
  discourseInterface.innerHTML = `
    <div style="max-width: 1200px; margin: 0 auto; padding: 20px;">
      <!-- Header con estadísticas -->
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 1px solid var(--primary-low);">
        <div>
          <h1 style="font-size: 2em; font-weight: 600; margin: 0 0 15px 0; color: var(--primary);">👥 Discourse Users</h1>
          <div style="display: flex; gap: 20px; flex-wrap: wrap;">
            <span style="display: flex; flex-direction: column; align-items: center; text-align: center;">
              <span id="totalUsers" style="font-size: 1.5em; font-weight: 600; color: var(--primary);">-</span>
              <span style="font-size: 0.9em; color: var(--primary-medium); margin-top: 5px;">users</span>
            </span>
            <span style="display: flex; flex-direction: column; align-items: center; text-align: center;">
              <span id="totalCountries" style="font-size: 1.5em; font-weight: 600; color: var(--primary);">-</span>
              <span style="font-size: 0.9em; color: var(--primary-medium); margin-top: 5px;">countries</span>
            </span>
          </div>
        </div>
        <div>
          <button id="refreshButton" style="background: var(--primary); color: var(--secondary); border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer;">
            🔄 Refresh
          </button>
        </div>
      </div>

      <!-- Filtros -->
      <div style="background: var(--highlight-low); padding: 20px; border-radius: 4px; margin-bottom: 30px;">
        <div style="display: flex; gap: 20px; align-items: end; flex-wrap: wrap;">
          <div style="display: flex; flex-direction: column; gap: 8px;">
            <label style="font-weight: 600; font-size: 0.9em; color: var(--primary);">Filter by country:</label>
            <select id="countryFilter" style="padding: 8px 12px; border: 1px solid var(--primary-low); border-radius: 4px; font-size: 14px; min-width: 200px; background: var(--secondary); color: var(--primary);">
              <option value="all">All countries</option>
            </select>
          </div>
          
          <div style="display: flex; flex-direction: column; gap: 8px;">
            <label style="font-weight: 600; font-size: 0.9em; color: var(--primary);">Search user:</label>
            <input 
              type="text" 
              id="searchInput"
              placeholder="First name, last name, email or username..."
              style="padding: 8px 12px; border: 1px solid var(--primary-low); border-radius: 4px; font-size: 14px; min-width: 200px; background: var(--secondary); color: var(--primary);"
            />
          </div>
          
          <div style="display: flex; flex-direction: column; gap: 8px;">
            <button id="clearFiltersButton" style="background: var(--primary-medium); color: var(--secondary); border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer;">
              🗑️ Clear filters
            </button>
          </div>
        </div>
      </div>

      <!-- Lista de usuarios -->
      <div id="usersContent" style="display: flex; flex-direction: column; gap: 20px;">
        <div style="text-align: center; padding: 60px 20px; color: var(--primary-medium);">
          <div style="font-size: 3em; margin-bottom: 20px;">⏳</div>
          <p>Loading Discourse users...</p>
        </div>
      </div>
    </div>
  `;

  // Insertar en el contenedor principal
  const mainOutletWrapper = document.getElementById('main-outlet-wrapper');
  if (mainOutletWrapper) {
    mainOutletWrapper.appendChild(discourseInterface);
  }

  // Cargar usuarios
  loadDiscourseUsers();

  // Agregar event listeners
  addEventListeners();
}

function hideDiscourseUsersInterface() {
  try {
    // Ocultar la interfaz de Discourse si existe
    const discourseInterface = document.querySelector('.discourse-users-interface');
    if (discourseInterface && discourseInterface.parentNode) {
      discourseInterface.remove();
    }
    
    // Restaurar el contenido principal de Discourse
    const mainOutlet = document.getElementById('main-outlet');
    if (mainOutlet) {
      mainOutlet.style.display = 'block';
      // Forzar un refresh del contenido si es necesario
      if (mainOutlet.children.length === 0) {
        // Si el main-outlet está vacío, Discourse puede necesitar recargar
        window.location.reload();
      }
    }
  } catch (e) {
    console.warn('Error al ocultar interfaz de Discourse:', e);
    // En caso de error, asegurar que el contenido principal esté visible
    const mainOutlet = document.getElementById('main-outlet');
    if (mainOutlet) {
      mainOutlet.style.display = 'block';
    }
  }
}

// Variables globales para el estado
let allUsers = {};
let allCountries = [];

async function loadDiscourseUsers() {
  console.log("=== SIDEBAR DEBUG - LOADING USERS ===");
  try {
    console.log("Fetching from /discourse/users/api");
    const response = await fetch('/discourse/users/api');
    console.log("Response status:", response.status);
    console.log("Response ok:", response.ok);
    
    const data = await response.json();
    console.log("=== SIDEBAR DEBUG - API RESPONSE ===");
    console.log("Data received:", data);
    console.log("Data type:", typeof data);
    console.log("Data keys:", Object.keys(data || {}));
    
    if (data.success) {
      console.log("Success response, using users_by_country");
      allUsers = data.users_by_country;
      allCountries = Object.keys(allUsers).sort();
      
      updateStats(data);
      populateCountryFilter();
      displayUsers(allUsers);
    } else if (data && typeof data === 'object' && !data.success && !data.error) {
      console.log("Direct object response (grouped by country)");
      allUsers = data;
      allCountries = Object.keys(allUsers).sort();
      
      console.log("Countries found:", allCountries);
      console.log("Users by country:", allUsers);
      
      updateStats({ total_users: Object.values(allUsers).flat().length });
      populateCountryFilter();
      displayUsers(allUsers);
    } else {
      console.error("Error response or unexpected data format:", data);
      showError(data.error || 'Error loading users');
    }
  } catch (error) {
    console.error("=== SIDEBAR DEBUG - ERROR ===");
    console.error("Error:", error);
    console.error("Error message:", error.message);
    showError('Connection error: ' + error.message);
  }
}

function updateStats(data) {
  const totalElement = document.getElementById('totalUsers');
  const countriesElement = document.getElementById('totalCountries');
  
  if (totalElement) totalElement.textContent = data.total_users;
  if (countriesElement) countriesElement.textContent = allCountries.length;
}

function populateCountryFilter() {
  const select = document.getElementById('countryFilter');
  if (!select) return;
  
  select.innerHTML = '<option value="all">All countries</option>';
  
  allCountries.forEach(country => {
    const option = document.createElement('option');
    option.value = country;
    option.textContent = country === 'No country' ? '🌍 No country specified' : country;
    select.appendChild(option);
  });
}

function filterUsers() {
  const countryFilter = document.getElementById('countryFilter');
  const searchInput = document.getElementById('searchInput');
  
  if (!countryFilter || !searchInput) return;
  
  const selectedCountry = countryFilter.value;
  const searchTerm = searchInput.value.toLowerCase();
  
  let filteredUsers = {};
  
  Object.keys(allUsers).forEach(country => {
    if (selectedCountry === 'all' || country === selectedCountry) {
      const countryUsers = allUsers[country];
      
      // Safety check: ensure countryUsers is an array
      if (!Array.isArray(countryUsers)) {
        console.warn(`Country ${country} data is not an array during filtering:`, countryUsers);
        return;
      }
      
      const filteredCountryUsers = countryUsers.filter(user => 
        (user.firstname && user.firstname.toLowerCase().includes(searchTerm)) ||
        (user.lastname && user.lastname.toLowerCase().includes(searchTerm)) ||
        (user.email && user.email.toLowerCase().includes(searchTerm)) ||
        (user.username && user.username.toLowerCase().includes(searchTerm)) ||
        (user.country && user.country.toLowerCase().includes(searchTerm)) ||
        (user.location && user.location.toLowerCase().includes(searchTerm))
      );
      
      if (filteredCountryUsers.length > 0) {
        filteredUsers[country] = filteredCountryUsers;
      }
    }
  });
  
  displayUsers(filteredUsers);
}

function displayUsers(users) {
  const content = document.getElementById('usersContent');
  if (!content) return;
  
  if (Object.keys(users).length === 0) {
    content.innerHTML = `
      <div style="text-align: center; padding: 60px 20px; color: var(--primary-medium);">
        <div style="font-size: 4em; margin-bottom: 20px;">🔍</div>
        <h3 style="margin: 0 0 10px 0; color: var(--primary);">No users found</h3>
        <p style="margin: 0; font-size: 1.1em;">Try adjusting the filters or search with different terms.</p>
      </div>
    `;
    return;
  }
  
  let html = '';
  
  Object.keys(users).forEach(country => {
    const countryUsers = users[country];
    
    // Safety check: ensure countryUsers is an array
    if (!Array.isArray(countryUsers)) {
      console.warn(`Country ${country} data is not an array:`, countryUsers);
      return;
    }
    
    const countryDisplay = country === 'No country' ? '🌍 No country specified' : country;
    
    html += `
      <div style="background: var(--secondary); border: 1px solid var(--primary-low); border-radius: 4px; overflow: hidden;">
        <div style="display: flex; justify-content: space-between; align-items: center; padding: 15px 20px; background: var(--highlight-low); border-bottom: 1px solid var(--primary-low);">
          <h3 style="font-size: 1.2em; font-weight: 600; margin: 0; color: var(--primary);">${countryDisplay}</h3>
          <span style="background: var(--primary); color: var(--secondary); padding: 4px 10px; border-radius: 12px; font-size: 0.9em; font-weight: 600;">${countryUsers.length} users</span>
        </div>
        
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 10px; padding: 20px;">
          ${countryUsers.map(user => `
            <div style="display: flex; align-items: center; gap: 15px; padding: 15px; background: var(--secondary); border: 1px solid var(--primary-low); border-radius: 4px;">
              <div style="flex-shrink: 0;">
                ${user.avatar_template ? 
                  `<img src="${user.avatar_template}" alt="Avatar" style="width: 48px; height: 48px; border-radius: 50%; object-fit: cover;">` :
                  `<div style="width: 48px; height: 48px; border-radius: 50%; background: var(--primary); color: var(--secondary); display: flex; align-items: center; justify-content: center; font-weight: 600; font-size: 1.2em;">
                  ${getInitials(user.firstname, user.lastname)}
                  </div>`
                }
              </div>
              <div style="flex: 1; min-width: 0;">
                <div style="font-weight: 600; margin-bottom: 3px; font-size: 1.1em; color: var(--primary);">${user.firstname} ${user.lastname}</div>
                <div style="color: var(--primary); font-size: 0.85em; font-weight: 500; margin-bottom: 3px;">@${user.username}</div>
                <div style="color: var(--primary-medium); font-size: 0.9em; word-break: break-all; margin-bottom: 3px;">${user.email}</div>
                <div style="color: var(--primary-medium); font-size: 0.85em; font-weight: 500; margin-bottom: 3px;">Location: ${user.location || user.country}</div>
                <div style="color: var(--primary-low); font-size: 0.8em;">Level: ${user.trust_level}</div>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  });
  
  content.innerHTML = html;
}

function getInitials(firstname, lastname) {
  const first = firstname ? firstname.charAt(0).toUpperCase() : '';
  const last = lastname ? lastname.charAt(0).toUpperCase() : '';
  return first + last || '?';
}

function clearFilters() {
  const countryFilter = document.getElementById('countryFilter');
  const searchInput = document.getElementById('searchInput');
  
  if (countryFilter) countryFilter.value = 'all';
  if (searchInput) searchInput.value = '';
  
  filterUsers();
}

function showError(message) {
  const content = document.getElementById('usersContent');
  if (!content) return;
  
  content.innerHTML = `
    <div style="text-align: center; padding: 60px 20px; color: var(--danger);">
      <div style="font-size: 4em; margin-bottom: 20px;">❌</div>
      <h3 style="margin: 0 0 10px 0; color: var(--danger);">Error</h3>
      <p style="margin: 0; font-size: 1.1em;">${message}</p>
    </div>
  `;
}

function addEventListeners() {
  // Botón de actualizar
  const refreshButton = document.getElementById('refreshButton');
  if (refreshButton) {
    refreshButton.addEventListener('click', loadDiscourseUsers);
  }
  
  // Filtro de país
  const countryFilter = document.getElementById('countryFilter');
  if (countryFilter) {
    countryFilter.addEventListener('change', filterUsers);
  }
  
  // Campo de búsqueda
  const searchInput = document.getElementById('searchInput');
  if (searchInput) {
    searchInput.addEventListener('input', filterUsers);
  }
  
  // Botón de limpiar filtros
  const clearFiltersButton = document.getElementById('clearFiltersButton');
  if (clearFiltersButton) {
    clearFiltersButton.addEventListener('click', clearFilters);
  }
}
