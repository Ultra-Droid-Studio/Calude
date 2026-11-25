-- RateLimiter: oyuncu başına token-bucket. Hassas remote'lar için (Bölüm 26).
-- Örnek: RateLimiter.new(5, 1) → saniyede 1 dolan, en fazla 5 birikebilen hak.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type RateLimiter = typeof(setmetatable(
	{} :: { _capacity: number, _refillPerSecond: number, _buckets: { [any]: { tokens: number, last: number } } },
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	return setmetatable({
		_capacity = capacity,
		_refillPerSecond = refillPerSecond,
		_buckets = {},
	}, RateLimiter)
end

-- true → işleme izin ver, false → reddet
function RateLimiter.Check(self: RateLimiter, key: any, cost: number?): boolean
	local now = os.clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._capacity, last = now }
		self._buckets[key] = bucket
	end
	local elapsed = now - bucket.last
	bucket.tokens = math.min(self._capacity, bucket.tokens + elapsed * self._refillPerSecond)
	bucket.last = now
	local price = cost or 1
	if bucket.tokens >= price then
		bucket.tokens -= price
		return true
	end
	return false
end

-- Oyuncu ayrılınca çağrılır (bellek temizliği)
function RateLimiter.Forget(self: RateLimiter, key: any)
	self._buckets[key] = nil
end

return RateLimiter
