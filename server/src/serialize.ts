import type { User } from "@prisma/client";

/** Never send passwordHash to the client, under any route. `usernameLower`
 * is an internal lookup key — clients get `username` with its original
 * casing instead. */
export function publicUser(user: User) {
  const { passwordHash, usernameLower, ...rest } = user;
  return rest;
}
