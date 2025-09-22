import Component from "@ember/component";
import { ajax } from "discourse/lib/ajax";
import { computed } from "@ember/object";

export default Component.extend({
  loading: false,
  error: null,
  users: null,
  selectedCountry: "all",
  searchTerm: "",

  init() {
    this._super(...arguments);
    this.loadUsers();
  },

  countries: computed("users", function() {
    if (!this.users) return [];
    return Object.keys(this.users).sort();
  }),

  filteredUsers: computed("users", "selectedCountry", "searchTerm", function() {
    if (!this.users) return null;

    let filtered = { ...this.users };

    // Filtrar por país
    if (this.selectedCountry !== "all") {
      filtered = { [this.selectedCountry]: filtered[this.selectedCountry] || {} };
    }

    // Filtrar por término de búsqueda
    if (this.searchTerm) {
      const searchLower = this.searchTerm.toLowerCase();
      Object.keys(filtered).forEach(country => {
        filtered[country] = filtered[country].filter(user => 
          (user.firstname && user.firstname.toLowerCase().includes(searchLower)) ||
          (user.lastname && user.lastname.toLowerCase().includes(searchLower)) ||
          (user.email && user.email.toLowerCase().includes(searchLower)) ||
          (user.username && user.username.toLowerCase().includes(searchLower)) ||
          (user.country && user.country.toLowerCase().includes(searchLower))
        );
      });
    }

    // Eliminar países vacíos
    Object.keys(filtered).forEach(country => {
      if (filtered[country].length === 0) {
        delete filtered[country];
      }
    });

    return filtered;
  }),

  totalFilteredUsers: computed("filteredUsers", function() {
    if (!this.filteredUsers) return 0;
    return Object.values(this.filteredUsers).reduce((total, users) => total + users.length, 0);
  }),

  totalCountries: computed("filteredUsers", function() {
    if (!this.filteredUsers) return 0;
    return Object.keys(this.filteredUsers).length;
  }),

  actions: {
    loadUsers() {
      this.set("loading", true);
      this.set("error", null);

      ajax("/discourse/users", {
        method: "GET"
      })
      .then(response => {
        if (response.success) {
          this.set("users", response.users_by_country);
        } else {
          this.set("error", response.error || "Error desconocido");
        }
      })
      .catch(error => {
        this.set("error", error.message || "Error al cargar usuarios");
      })
      .finally(() => {
        this.set("loading", false);
      });
    },

    selectCountry(country) {
      this.set("selectedCountry", country);
    },

    updateSearchTerm(event) {
      this.set("searchTerm", event.target.value);
    },

    clearFilters() {
      this.set("selectedCountry", "all");
      this.set("searchTerm", "");
    }
  }
});
