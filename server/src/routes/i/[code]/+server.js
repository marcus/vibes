import { redirect } from "@sveltejs/kit";

export function GET({ params }) {
  throw redirect(307, `/invite/${encodeURIComponent(params.code)}`);
}
