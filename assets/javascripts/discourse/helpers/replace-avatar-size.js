import { helper } from "@ember/component/helper";

export function replaceAvatarSize([avatarTemplate]) {
  if (!avatarTemplate) return '';
  return avatarTemplate.replace('{size}', '48');
}

export default helper(replaceAvatarSize);
