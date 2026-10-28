extends Node
class_name NetworkConstants

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 4
const TICK_RATE_HZ: float = 30.0 # 30 network updates per second during combat wave
const TICK_DELTA: float = 1.0 / TICK_RATE_HZ

enum PeerRole {
	SOLO,
	HOST,
	CLIENT
}

enum PacketType {
	HANDSHAKE_REQUEST,
	HANDSHAKE_RESPONSE,
	LOBBY_UPDATE,
	PLAYER_INPUT,
	WAVE_START,
	WAVE_STATE_SNAPSHOT,
	WAVE_END,
	SHOP_ACTION,
	PLAYER_DIED
}
