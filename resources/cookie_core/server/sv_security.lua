local buckets = {}
local function allow(src,key,windowMs,maxCount)
  src=tonumber(src) or 0; key=tostring(key or 'default'); windowMs=math.max(100,tonumber(windowMs) or 1000); maxCount=math.max(1,tonumber(maxCount) or 1)
  local now=GetGameTimer(); buckets[src]=buckets[src] or {}; local b=buckets[src][key]
  if not b or now-b.t>=windowMs then buckets[src][key]={t=now,n=1}; return true end
  if b.n>=maxCount then return false end; b.n=b.n+1; return true
end
exports('Allow',allow)
AddEventHandler('playerDropped',function() buckets[source]=nil end)
