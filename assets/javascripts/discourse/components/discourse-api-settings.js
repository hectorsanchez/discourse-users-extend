import Component from "@ember/component";
import { ajax } from "discourse/lib/ajax";

export default Component.extend({
  dmu_discourse_api_key: "",
  dmu_discourse_api_username: "system",
  dmu_discourse_api_url: "",
  dmu_discourse_api_limit: 100,

  actions: {
    saveSettings() {
      ajax("/discourse/save_settings", {
        method: "POST",
        data: {
          dmu_discourse_api_key: this.dmu_discourse_api_key,
          dmu_discourse_api_username: this.dmu_discourse_api_username,
          dmu_discourse_api_url: this.dmu_discourse_api_url,
          dmu_discourse_api_limit: this.dmu_discourse_api_limit,
        },
      }).then(() => {
        // Mostrar mensaje de éxito
      });
    },
  },
});