// Earth radius in centimeters. Lower this number for more noticeble curvature.
#define EARTH_RADIUS 63781370
#define DPS_STR 1.5

// Better interpolation between RGB colors
// From: https://www.shadertoy.com/view/lsdGzN
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

// Due to how UE4 Custom nodes work, convenience functions have to be wrapped in a struct
struct Functions
{
	// Gets the distance from a ray point to its intersection with a sphere
    float rsIntersect(float3 r0, float3 rd, float3 s0, float sr)
    {
        float a = dot(rd, rd);
		float3 s0_r0 = r0-s0;
		float b = 2.0 * dot(rd, s0_r0);
		float c = dot(s0_r0, s0_r0) - (sr*sr);

		if (b*b - 4.0*a*c < 0.0)
		{
			return -1.0;
		}
		return (-b - sqrt((b*b) - 4.0*a*c)) / (2.0*a);
    }

	float invLerp(float from, float to, float value)
	{
		return (value - from) / (to - from);
	}

};

Functions f;
ColorFunctions c;

// Why run all this code if there's nothing to render?
if (Density <= 0) return float4(0,0,0,0);

float3 earthPos = float3(CameraPos.xy,-EARTH_RADIUS); // Assume the center of the earth is always straight down below the camera
float3 rayDir = normalize(Parameters.CameraVector); 
float intersectDistance = f.rsIntersect(CameraPos, rayDir, earthPos, EARTH_RADIUS+StartHeight);
float3 rayPos = CameraPos + intersectDistance*rayDir; // Start the ray at the inner shell set by StartHeight

if (intersectDistance > Depth) return float4(0,0,0,0); // There's something in front, abort

float3 endPos = rayPos + (f.rsIntersect(rayPos, rayDir, earthPos, EARTH_RADIUS+StopHeight)*rayDir);
float totalDistance = distance(rayPos,endPos);
float3 accumulator = float3(0,0,0);

float horizonAngle = dot(rayDir, float3(0,0,-1));
float horizonFade = pow(abs(horizonAngle), HorizonFadePower); // Blend with the skybox towards the horizon

float steps = round(lerp(MinSteps, MaxSteps, horizonAngle)); // Adjust number of steps depending on angle
float densityMult = Density/steps; // But keep the density constant!

float stepSize = distance(rayPos, endPos)/steps;
stepSize *= Jitter; // Jitter helps hide the stepping artifacts by making the step sizes slightly random each frame

if (rayPos.z > 0) // No point checking for auroras under 0 generally
{
	for (int i = 0; i < steps; i++)
	{
		float3 sampleStep = rayDir*stepSize*i; //How far from the start position to move
		float2 samplePos = (rayPos-sampleStep).xy;
		float heightSample = saturate(f.invLerp(0, totalDistance, length(sampleStep)));
		if (distance(CameraPos, samplePos) > Depth) return float4(accumulator*horizonFade,1); //We have gone behind an object, no need to keep going

		float colorSample = Tex.SampleLevel(TexSampler, samplePos/ColorSize+ColorOffset, 0).g; //Determine the color
		float3 color = c.iLerp(Color1, Color2, colorSample);

		float2 rdistortion = Tex.SampleLevel(TexSampler, samplePos/DistortionSize+DistortionOffset, 0).g-0.5; // Reuse the B channel of the texture to add distortion, creating the organic flowy look
		rdistortion *= DistortionStrength;

		float4 addVal = pow(Tex.SampleLevel(TexSampler, samplePos/MainTexSize + RTextureOffset+rdistortion, 0).r,MainPower); //Worley noise (or really just whatever you want if you change the texture)
		addVal *= Tex.SampleLevel(TexSampler, samplePos/TextureSize.x + GTextureOffset, 0).g; // Low frequency perlin
		addVal *= Tex.SampleLevel(TexSampler, samplePos/TextureSize.y + BTextureOffset, 0).b; // High frequency perlin
		addVal *= densityMult; // Ensure consistent density with step changes

		float heightMultiplier = HG.SampleLevel(TexSampler, float2(0.5, heightSample), 0).r; //This would probably be faster with math rather than sampling another texture but I am bad at math

		accumulator += addVal*color*heightMultiplier; //Auroras glow so we can just keep stacking this on top as we move further into the field

		
	}
	return float4(accumulator*horizonFade,1); //We made it to the other side!
}
return float4(0,0,0,0);