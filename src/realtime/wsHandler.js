/**
 * Direct WebSocket Forwarder to Durable Object
 * Preserves raw WebSocket upgrade headers without reconstruction.
 */
export async function handleWebSocketUpgrade(request, env) {
  const roomId = env.CHAT_ROOM.idFromName("global_room");
  return env.CHAT_ROOM.get(roomId).fetch(request);
}
