
#ifndef SKYBOX_TONE_MAP_HLSL
#define SKYBOX_TONE_MAP_HLSL

#include "GBuffer.hlsl"
#include "FramebufferFlat.hlsl"

//--------------------------------------------------------------------------------------
// ����, ��պе�
// ʹ����պм�������Ⱦ
//--------------------------------------------------------------------------------------
TextureCube<float4> g_SkyboxTexture : register(t5);
Texture2DMS<float, MSAA_SAMPLES> g_DepthTexture : register(t6);

// ������ز����ĳ�����Ⱦ������
Texture2DMS<float4, MSAA_SAMPLES> g_LitTexture : register(t7);
// ������ɫ������д����ز���UAV����ʹ��1D���������ʾ
StructuredBuffer<uint2> g_FlatLitTexture : register(t8);

struct SkyboxVSOut
{
    float4 posViewport : SV_Position;
    float3 skyboxCoord : skyboxCoord;
};

SkyboxVSOut SkyboxVS(VertexPosNormalTex input)
{
    SkyboxVSOut output;
    
    // ע�⣺��Ҫ�ƶ���պв�ȷ�����ֵΪ1(����ü�)
    output.posViewport = mul(float4(input.posL, 0.0f), g_ViewProj).xyww;
    output.skyboxCoord = input.posL;
    
    return output;
}

float4 SkyboxPS(SkyboxVSOut input) : SV_Target
{
    // ����ṩ��1D��MSAA������Ⱦ����������ʹ����
    uint2 dims;
    g_FlatLitTexture.GetDimensions(dims.x, dims.y);
    bool useFlatLitBuffer = dims.x > 0;
    
    uint2 coords = input.posViewport.xy;

    float3 lit = float3(0.0f, 0.0f, 0.0f);
    float skyboxSamples = 0.0f;
#if MSAA_SAMPLES <= 1
    [unroll]
#endif
    for (unsigned int sampleIndex = 0; sampleIndex < MSAA_SAMPLES; ++sampleIndex)
    {
        float depth = g_DepthTexture.Load(coords, sampleIndex);

        // �����պе�״̬��ע�⣺����Z!��  
        if (depth <= 0.0f && !g_VisualizeLightCount)
        {
            ++skyboxSamples;
        }
        else
        {
            float3 sampleLit;
            [branch]
            if (useFlatLitBuffer)
            {
                sampleLit = UnpackRGBA16(g_FlatLitTexture[GetFramebufferSampleAddress(coords, sampleIndex)]).xyz;
            }
            else
            {
                sampleLit = g_LitTexture.Load(coords, sampleIndex).xyz;
            }
            
            lit += sampleLit;
        }
    }

    // �������û�г�����Ⱦ������Ⱦ��պ�
    [branch]
    if (skyboxSamples > 0)
    {
        float3 skybox = g_SkyboxTexture.Sample(g_SamplerDiffuse, input.skyboxCoord).xyz;
        lit += skyboxSamples * skybox;
    }
    
    // Resolve ���ز���(�򵥺����˲�)
    return float4(lit * rcp(MSAA_SAMPLES), 1.0f);
}


#endif // SKYBOX_TONE_MAP_HLSL
