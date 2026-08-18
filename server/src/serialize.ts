import type { User } from "@prisma/client";

/** Never send passwordHash to the client, under any route. */
export function publicUser(user: User) {
  const { passwordHash, ...rest } = user;
  return rest;
}
