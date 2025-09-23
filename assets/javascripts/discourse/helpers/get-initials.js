import { helper } from "@ember/component/helper";

export function getInitials([firstname, lastname]) {
  const first = firstname ? firstname.charAt(0).toUpperCase() : '';
  const last = lastname ? lastname.charAt(0).toUpperCase() : '';
  return first + last || '?';
}

export default helper(getInitials);