#define DPS_STR 1.5

//From: https://www.shadertoy.com/view/lsdGzN
struct ColorFunctions
{
	float getsat(float3 c)
	{
		float mi = min(min(c.x,c.y),c.z);
		float ma = max(max(c.x,c.y),c.z);
		return (ma - mi)/(ma+ 1e-7);
	}

	float3 iLerp(float3 a, float3 b, float x)
	{
		float3 ic = lerp(a, b, x) + float3(1e-6,0.0,0.0);
		float sd = abs(getsat(ic) - lerp(getsat(a), getsat(b), x));
		float3 dir = normalize(float3(2*ic.x - ic.y - ic.z, 2*ic.y - ic.x - ic.z, 2*ic.z - ic.y - ic.x));
		float lgt = dot(float3(1,1,1), ic);
		float ff = dot(dir, normalize(ic));
		ic += DPS_STR*dir*sd*ff*lgt;
		return saturate(ic);
	}

};

ColorFunctions c;

struct Functions
{

	float invLerp(float from, float to, float value)
	{
		return (value - from) / (to - from);
	}

};

Functions f;

// This essentially throws a single ray into the depth buffer, to map the same color as the aurora above

if (Depth > 10000000) return float4(0,0,0,0);

float3 rayDir = normalize(Parameters.CameraVector);
float3 rayPos = CameraPos-rayDir*Depth;
float2 samplePos = rayPos.xy;

float colorSample = Tex.SampleLevel(TexSampler, samplePos/ColorSize+ColorOffset, 0).g;
float3 color = c.iLerp(Color1, Color2, colorSample);

float2 rdistortion = Tex.SampleLevel(TexSampler, samplePos/DistortionSize+DistortionOffset, 0).g-0.5;
rdistortion *= DistortionStrength;
float4 addVal = pow(Tex.SampleLevel(TexSampler, samplePos/MainTexSize + RTextureOffset+rdistortion, 0).r,MainPower);
addVal *= Density*saturate(f.invLerp(MaxDistance, 0, StartHeight-rayPos.z)); //Fade out as we get further from where the aurora starts

return float4(addVal*color,0);