
#ifndef COMPUTE_SHADER_TILE_HLSL
#define COMPUTE_SHADER_TILE_HLSL

#include "GBuffer.hlsl"
#include "FramebufferFlat.hlsl"
#include "ForwardTileInfo.hlsl"


RWStructuredBuffer<TileInfo> g_TilebufferRW : register(u0);

RWStructuredBuffer<uint2> g_Framebuffer : register(u1);

groupshared uint s_MinZ;
groupshared uint s_MaxZ;

// ��ǰtile�Ĺ����б�
groupshared uint s_TileLightIndices[MAX_LIGHTS >> 3];
groupshared uint s_TileNumLights;

// ��ǰtile����Ҫ��������ɫ�������б�
// ���ǽ�����16λx/y��������һ��uint����ʡ�����ڴ�ռ�
groupshared uint s_PerSamplePixels[COMPUTE_SHADER_TILE_GROUP_SIZE];
groupshared uint s_NumPerSamplePixels;

//--------------------------------------------------------------------------------------
// ����д�����ǵ�1D MSAA UAV
void WriteSample(uint2 coords, uint sampleIndex, float4 value)
{
    g_Framebuffer[GetFramebufferSampleAddress(coords, sampleIndex)] = PackRGBA16(value);
}

// ������<=16λ������ֵ���������uint
uint PackCoords(uint2 coords)
{
    return coords.y << 16 | coords.x;
}
// ������uint���������<=16λ������ֵ
uint2 UnpackCoords(uint coords)
{
    return uint2(coords & 0xFFFF, coords >> 16);
}


void ConstructFrustumPlanes(uint3 groupId, float minTileZ, float maxTileZ, 
                            out float4 frustumPlanes[6])
{
    // ע�⣺����ļ���ÿ���ֿ鶼��ͳһ��(���磺����Ҫÿ���̶߳�ִ��)�������۵�����
    // ���ǿ���ֻ����Ϊÿ���ֿ�Ԥ������׶ƽ�棬Ȼ�󽫽���ŵ�һ��������������...
    // ֻ�е�ͶӰ����ı��ʱ�����Ҫ�仯����Ϊ�������ڹ۲�ռ�ִ�У�
    // Ȼ�����Ǿ�ֻ��Ҫ�����/Զƽ������������ʵ�ʵļ����塣
    // ������������ͬ��/�ֲ����ݹ���(Local Data Share, LDS)��ȫ���ڴ�Ѱ�ҵĿ������ܺ���С����ѧһ���࣬��ֵ�ó��ԡ�
    
    // ��[0, 1]���ҳ�����/ƫ��
    float2 tileScale = float2(g_FramebufferDimensions.xy) * rcp(float(2 * COMPUTE_SHADER_TILE_GROUP_DIM));
    float2 tileBias = tileScale - float2(groupId.xy);

    // ���㵱ǰ�ֿ���׶���ͶӰ����
    float4 c1 = float4(g_Proj._11 * tileScale.x, 0.0f, tileBias.x, 0.0f);
    float4 c2 = float4(0.0f, -g_Proj._22 * tileScale.y, tileBias.y, 0.0f);
    float4 c4 = float4(0.0f, 0.0f, 1.0f, 0.0f);

    // Gribb/Hartmann����ȡ��׶��ƽ��
    // ����
    frustumPlanes[0] = c4 - c1; // �Ҳü�ƽ�� 
    frustumPlanes[1] = c4 + c1; // ��ü�ƽ��
    frustumPlanes[2] = c4 - c2; // �ϲü�ƽ��
    frustumPlanes[3] = c4 + c2; // �²ü�ƽ��
    // ��/Զƽ��
    frustumPlanes[4] = float4(0.0f, 0.0f, 1.0f, -minTileZ);
    frustumPlanes[5] = float4(0.0f, 0.0f, -1.0f, maxTileZ);
    
    // ��׼����׶��ƽ��(��/Զƽ���Ѿ���׼��)
    [unroll]
    for (uint i = 0; i < 4; ++i)
    {
        frustumPlanes[i] *= rcp(length(frustumPlanes[i].xyz));
    }
}

[numthreads(COMPUTE_SHADER_TILE_GROUP_DIM, COMPUTE_SHADER_TILE_GROUP_DIM, 1)]
void ComputeShaderTileDeferredCS(uint3 groupId : SV_GroupID,
                                 uint3 dispatchThreadId : SV_DispatchThreadID,
                                 uint3 groupThreadId : SV_GroupThreadID,
                                 uint groupIndex : SV_GroupIndex
                                 )
{
    //
    // ��ȡ�������ݣ����㵱ǰ�ֿ����׶��
    //
    
    uint2 globalCoords = dispatchThreadId.xy;
    
    SurfaceData surfaceSamples[MSAA_SAMPLES];
    ComputeSurfaceDataFromGBufferAllSamples(globalCoords, surfaceSamples);
        
    // Ѱ�����в����е�Z�߽�
    float minZSample = g_CameraNearFar.y;
    float maxZSample = g_CameraNearFar.x;
    {
        [unroll]
        for (uint sample = 0; sample < MSAA_SAMPLES; ++sample)
        {
            // �������պл������Ƿ�������ɫ
            float viewSpaceZ = surfaceSamples[sample].posV.z;
            bool validPixel =
                 viewSpaceZ >= g_CameraNearFar.x &&
                 viewSpaceZ < g_CameraNearFar.y;
            [flatten]
            if (validPixel)
            {
                minZSample = min(minZSample, viewSpaceZ);
                maxZSample = max(maxZSample, viewSpaceZ);
            }
        }
    }
    
    // ��ʼ�������ڴ��еĹ����б��Z�߽�
    if (groupIndex == 0)
    {
        s_TileNumLights = 0;
        s_NumPerSamplePixels = 0;
        s_MinZ = 0x7F7FFFFF; // ��󸡵���
        s_MaxZ = 0;
    }

    GroupMemoryBarrierWithGroupSync();

    // ע�⣺������Խ��в��й�Լ(parallel reduction)���Ż�������������ʹ����MSAA��
    // �洢�˶��ز����������ڹ����ڴ��У������ӵĹ����ڴ�ѹ��ʵ����**��С**�ں˵���
    // �������ٶȡ���Ϊ����������õ�����£���Ŀǰ���е��ͷֿ�(tile)��С�ĵļܹ��ϣ�
    // ���й�Լ���ٶ�����Ҳ�ǲ���ġ�
    // ֻ������ʵ�ʺϷ����������������С�
    if (maxZSample >= minZSample)
    {
        InterlockedMin(s_MinZ, asuint(minZSample));
        InterlockedMax(s_MaxZ, asuint(maxZSample));
    }

    GroupMemoryBarrierWithGroupSync();
    
    float minTileZ = asfloat(s_MinZ);
    float maxTileZ = asfloat(s_MaxZ);
    float4 frustumPlanes[6];
    ConstructFrustumPlanes(groupId, minTileZ, maxTileZ, frustumPlanes);
    
    //
    // �Ե�ǰ�ֿ�(tile)���й��ղü�
    //
    
    // NOTE: This is currently necessary rather than just using SV_GroupIndex to work
    // around a compiler bug on Fermi.
    // uint groupIndex = groupThreadId.y * COMPUTE_SHADER_TILE_GROUP_DIM + groupThreadId.x;
    // ע�����׼ܹ��Ǻܾ���ǰ���Կ��ˣ������ֱ��ʹ��SV_GroupIndex
 
    uint totalLights, dummy;
    g_Light.GetDimensions(totalLights, dummy);

    // ����ÿ���̳߳е�һ���ֹ�Դ����ײ������
    for (uint lightIndex = groupIndex; lightIndex < totalLights; lightIndex += COMPUTE_SHADER_TILE_GROUP_SIZE)
    {
        PointLight light = g_Light[lightIndex];
                
        // ���Դ������tile��׶�����ײ���
        bool inFrustum = true;
        [unroll]
        for (uint i = 0; i < 6; ++i)
        {
            float d = dot(frustumPlanes[i], float4(light.posV, 1.0f));
            inFrustum = inFrustum && (d >= -light.attenuationEnd);
        }

        [branch]
        if (inFrustum)
        {
            // ������׷�ӵ��б���
            uint listIndex;
            InterlockedAdd(s_TileNumLights, 1, listIndex);
            s_TileLightIndices[listIndex] = lightIndex;
        }
    }

    GroupMemoryBarrierWithGroupSync();
    
    uint numLights = s_TileNumLights;
    //
    // ֻ��������Ļ���������(�����ֿ���ܳ�����Ļ��Ե)
    // 
    if (all(globalCoords < g_FramebufferDimensions.xy))
    {
        [branch]
        if (g_VisualizeLightCount)
        {
            [unroll]
            for (uint sample = 0; sample < MSAA_SAMPLES; ++sample)
            {
                WriteSample(globalCoords, sample, (float(s_TileNumLights) / 255.0f).xxxx);
            }
        }
        else if (numLights > 0)
        {
            bool perSampleShading = RequiresPerSampleShading(surfaceSamples);
            // ��������ɫ���ӻ�
            [branch]
            if (g_VisualizePerSampleShading && perSampleShading)
            {
                [unroll]
                for (uint sample = 0; sample < MSAA_SAMPLES; ++sample)
                {
                    WriteSample(globalCoords, sample, float4(1, 0, 0, 1));
                }
            }
            else
            {
                float3 lit = float3(0.0f, 0.0f, 0.0f);
                for (uint tileLightIndex = 0; tileLightIndex < numLights; ++tileLightIndex)
                {
                    PointLight light = g_Light[s_TileLightIndices[tileLightIndex]];
                    AccumulateColor(surfaceSamples[0], light, lit);
                }

                // ��������0�Ľ��
                WriteSample(globalCoords, 0, float4(lit, 1.0f));
                        
                [branch]
                if (perSampleShading)
                {
#if DEFER_PER_SAMPLE
                    // ������Ҫ������������ɫ�������б�
                    uint listIndex;
                    InterlockedAdd(s_NumPerSamplePixels, 1, listIndex);
                    s_PerSamplePixels[listIndex] = PackCoords(globalCoords);
#else
                    // �Ե�ǰ���ص���������������ɫ
                    for (uint sample = 1; sample < MSAA_SAMPLES; ++sample)
                    {
                        float3 litSample = float3(0.0f, 0.0f, 0.0f);
                        for (uint tileLightIndex = 0; tileLightIndex < numLights; ++tileLightIndex)
                        {
                            PointLight light = g_Light[s_TileLightIndices[tileLightIndex]];
                            AccumulateColor(surfaceSamples[sample], light, litSample);
                        }
                        WriteSample(globalCoords, sample, float4(litSample, 1.0f));
                    }
#endif
                }
                else
                {
                    // ���������������ɫ��������0�Ľ��Ҳ���Ƶ�����������
                    [unroll]
                    for (uint sample = 1; sample < MSAA_SAMPLES; ++sample)
                    {
                        WriteSample(globalCoords, sample, float4(lit, 1.0f));
                    }
                }
            }
        }
        else
        {
            // û�й��յ�Ӱ�죬�����������
            [unroll]
            for (uint sample = 0; sample < MSAA_SAMPLES; ++sample)
            {
                WriteSample(globalCoords, sample, float4(0.0f, 0.0f, 0.0f, 0.0f));
            }
        }
    }

#if DEFER_PER_SAMPLE && MSAA_SAMPLES > 1
    GroupMemoryBarrierWithGroupSync();

    // ���ڴ�����Щ��Ҫ��������ɫ������
    // ע�⣺ÿ��������Ҫ�����MSAA_SAMPLES - 1����ɫpasses
    const uint shadingPassesPerPixel = MSAA_SAMPLES - 1;
    uint globalSamples = s_NumPerSamplePixels * shadingPassesPerPixel;

    for (uint globalSample = groupIndex; globalSample < globalSamples; globalSample += COMPUTE_SHADER_TILE_GROUP_SIZE) {
        uint listIndex = globalSample / shadingPassesPerPixel;
        uint sampleIndex = globalSample % shadingPassesPerPixel + 1;        // ����0�Ѿ���������� 

        uint2 sampleCoords = UnpackCoords(s_PerSamplePixels[listIndex]);
        SurfaceData surface = ComputeSurfaceDataFromGBufferSample(sampleCoords, sampleIndex);

        float3 lit = float3(0.0f, 0.0f, 0.0f);
        for (uint tileLightIndex = 0; tileLightIndex < numLights; ++tileLightIndex) {
            PointLight light = g_Light[s_TileLightIndices[tileLightIndex]];
            AccumulateColor(surface, light, lit);
        }
        WriteSample(sampleCoords, sampleIndex, float4(lit, 1.0f));
    }
#endif
}

[numthreads(COMPUTE_SHADER_TILE_GROUP_DIM, COMPUTE_SHADER_TILE_GROUP_DIM, 1)]
void ComputeShaderTileForwardCS(uint3 groupId : SV_GroupID,
                                uint3 dispatchThreadId : SV_DispatchThreadID,
                                uint3 groupThreadId : SV_GroupThreadID,
                                uint groupIndex : SV_GroupIndex
                                )
{
    //
    // ��ȡ������ݣ����㵱ǰ�ֿ����׶��
    //
    
    uint2 globalCoords = dispatchThreadId.xy;
    
    // Ѱ�����в����е�Z�߽�
    float minZSample = g_CameraNearFar.y;
    float maxZSample = g_CameraNearFar.x;
    {
        [unroll]
        for (uint sample = 0; sample < MSAA_SAMPLES; ++sample)
        {
            // ����ȡ������Ȼ�������Zֵ
            float zBuffer = g_GBufferTextures[3].Load(globalCoords, sample);
            float viewSpaceZ = g_Proj._m32 / (zBuffer - g_Proj._m22);
            
            // �������պл������Ƿ�������ɫ
            bool validPixel =
                 viewSpaceZ >= g_CameraNearFar.x &&
                 viewSpaceZ < g_CameraNearFar.y;
            [flatten]
            if (validPixel)
            {
                minZSample = min(minZSample, viewSpaceZ);
                maxZSample = max(maxZSample, viewSpaceZ);
            }
        }
    }
    
    // ��ʼ�������ڴ��еĹ����б��Z�߽�
    if (groupIndex == 0)
    {
        s_TileNumLights = 0;
        s_NumPerSamplePixels = 0;
        s_MinZ = 0x7F7FFFFF; // ��󸡵���
        s_MaxZ = 0;
    }

    GroupMemoryBarrierWithGroupSync();
    
    // ע�⣺������Խ��в��й�Լ(parallel reduction)���Ż�������������ʹ����MSAA��
    // �洢�˶��ز����������ڹ����ڴ��У������ӵĹ����ڴ�ѹ��ʵ����**��С**�ں˵���
    // �������ٶȡ���Ϊ����������õ�����£���Ŀǰ���е��ͷֿ�(tile)��С�ĵļܹ��ϣ�
    // ���й�Լ���ٶ�����Ҳ�ǲ���ġ�
    // ֻ������ʵ�ʺϷ����������������С�
    if (maxZSample >= minZSample)
    {
        InterlockedMin(s_MinZ, asuint(minZSample));
        InterlockedMax(s_MaxZ, asuint(maxZSample));
    }

    GroupMemoryBarrierWithGroupSync();

    float minTileZ = asfloat(s_MinZ);
    float maxTileZ = asfloat(s_MaxZ);
    float4 frustumPlanes[6];
    ConstructFrustumPlanes(groupId, minTileZ, maxTileZ, frustumPlanes);
    
    //
    // �Ե�ǰ�ֿ�(tile)���й��ղü�
    //
    
    uint totalLights, dummy;
    g_Light.GetDimensions(totalLights, dummy);

    // ���㵱ǰtile�ڹ��������������е�λ��
    uint2 dispatchWidth = (g_FramebufferDimensions.x + COMPUTE_SHADER_TILE_GROUP_DIM - 1) / COMPUTE_SHADER_TILE_GROUP_DIM;
    uint tilebufferIndex = groupId.y * dispatchWidth + groupId.x;
    
    // ����ÿ���̳߳е�һ���ֹ�Դ����ײ������
    [loop]
    for (uint lightIndex = groupIndex; lightIndex < totalLights; lightIndex += COMPUTE_SHADER_TILE_GROUP_SIZE)
    {
        PointLight light = g_Light[lightIndex];
                
        // ���Դ������tile��׶�����ײ���
        bool inFrustum = true;
        [unroll]
        for (uint i = 0; i < 6; ++i)
        {
            float d = dot(frustumPlanes[i], float4(light.posV, 1.0f));
            inFrustum = inFrustum && (d >= -light.attenuationEnd);
        }

        [branch]
        if (inFrustum)
        {
            // ������׷�ӵ��б���
            uint listIndex;
            InterlockedAdd(s_TileNumLights, 1, listIndex);
            g_TilebufferRW[tilebufferIndex].tileLightIndices[listIndex] = lightIndex;
        }
    }
    
    GroupMemoryBarrierWithGroupSync();
    
    if (groupIndex == 0)
    {
        g_TilebufferRW[tilebufferIndex].tileNumLights = s_TileNumLights;
    }
}

#endif // COMPUTE_SHADER_TILE_HLSL
