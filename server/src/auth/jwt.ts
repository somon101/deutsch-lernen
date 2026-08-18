import jwt from "jsonwebtoken";
import { env } from "../env.js";

export interface AuthTokenPayload {
  sub: string; // user id
}

const EXPIRES_IN = "30d";

export function signToken(userId: string): string {
  const payload: AuthTokenPayload = { sub: userId };
  return jwt.sign(payload, env.jwtSecret, { expiresIn: EXPIRES_IN });
}

export function verifyToken(token: string): AuthTokenPayload | null {
  try {
    return jwt.verify(token, env.jwtSecret) as AuthTokenPayload;
  } catch {
    return null;
  }
}
