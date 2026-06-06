#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));

function readEnvFile(path) {
  try {
    const contents = readFileSync(path, "utf8");
    for (const line of contents.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
      if (!match) continue;
      if (process.env[match[1]] === undefined) {
        process.env[match[1]] = match[2].replace(/^(['"])(.*)\1$/, "$2");
      }
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function render(template, values) {
  return template.replace(/\$\{([A-Z0-9_]+)\}/g, (_, name) => {
    if (values[name] === undefined) {
      throw new Error(`Missing template value: ${name}`);
    }
    return values[name];
  });
}

readEnvFile(process.env.DEPLOY_ENV_FILE ?? join(root, ".env.deploy"));

const values = {
  APP_NAME: process.env.APP_NAME ?? "vibes",
  DEPLOY_DOMAIN: required("DEPLOY_DOMAIN"),
  DEPLOY_PATH: process.env.DEPLOY_PATH ?? `/var/www/${process.env.APP_NAME ?? "vibes"}`,
  SERVICE_NAME: process.env.SERVICE_NAME ?? process.env.APP_NAME ?? "vibes",
  SERVICE_HOST: process.env.SERVICE_HOST ?? "127.0.0.1",
  SERVICE_PORT: process.env.SERVICE_PORT ?? "3136",
  SERVICE_USER: process.env.SERVICE_USER ?? process.env.DEPLOY_USER ?? "root",
};

const outputDir = join(root, "deploy", "rendered");
mkdirSync(outputDir, { recursive: true });

const nginx = render(readFileSync(join(root, "deploy", "nginx.conf.template"), "utf8"), values);
const service = render(readFileSync(join(root, "deploy", "vibes.service.template"), "utf8"), values);

writeFileSync(join(outputDir, `${values.APP_NAME}.nginx.conf`), nginx);
writeFileSync(join(outputDir, `${values.SERVICE_NAME}.service`), service);

console.log(`Rendered deploy config to ${outputDir}`);
