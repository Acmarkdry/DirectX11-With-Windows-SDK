#ifndef FXAA_HLSL_INC
#define FXAA_HLSL_INC

#ifndef FXAA_QUALITY__PRESET
#define FXAA_QUALITY__PRESET 39
#endif

//   FXAA ���� - ���������еȶ���
#if (FXAA_QUALITY__PRESET == 10)
#define FXAA_QUALITY__PS 3 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.5, 3.0, 12.0 };
#endif

#if (FXAA_QUALITY__PRESET == 11)
#define FXAA_QUALITY__PS 4 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 3.0, 12.0 };
#endif

#if (FXAA_QUALITY__PRESET == 12)
#define FXAA_QUALITY__PS 5 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 4.0, 12.0 };
#endif

#if (FXAA_QUALITY__PRESET == 13)
#define FXAA_QUALITY__PS 6 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 4.0, 12.0 };
#endif

#if (FXAA_QUALITY__PRESET == 14)
#define FXAA_QUALITY__PS 7 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 4.0, 12.0 };
#endif

#if (FXAA_QUALITY__PRESET == 15)
#define FXAA_QUALITY__PS 8 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 12.0 };
#endif

//   FXAA ���� - �еȣ����ٶ���
#if (FXAA_QUALITY__PRESET == 20)
#define FXAA_QUALITY__PS 3 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.5, 2.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 21)
#define FXAA_QUALITY__PS 4 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 22)
#define FXAA_QUALITY__PS 5 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 23)
#define FXAA_QUALITY__PS 6 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 24)
#define FXAA_QUALITY__PS 7 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 3.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 25)
#define FXAA_QUALITY__PS 8 
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 26)
#define FXAA_QUALITY__PS 9
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 27)
#define FXAA_QUALITY__PS 10
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 28)
#define FXAA_QUALITY__PS 11
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
#endif

#if (FXAA_QUALITY__PRESET == 29)
#define FXAA_QUALITY__PS 12
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
#endif

//   FXAA ���� - ��
#if (FXAA_QUALITY__PRESET == 39)
#define FXAA_QUALITY__PS 12
static const float s_SampleDistances[FXAA_QUALITY__PS] = { 1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0 };
#endif

cbuffer CB : register(b0)
{
    float2 g_TexelSize;
    
    // Ӱ�������̶�
    // 1.00 - ���
    // 0.75 - Ĭ���˲�ֵ
    // 0.50 - ���������Ƴ����ٵ�����������
    // 0.25 - �����ص�
    // 0.00 - ��ȫ�ص�
    float g_QualitySubPix;
    
    // ����ֲ��Աȶȵ���ֵ����
    // 0.333 - �ǳ��ͣ����죩
    // 0.250 - ������
    // 0.166 - Ĭ��
    // 0.125 - ������
    // 0.063 - �ǳ��ߣ�������
    float g_QualityEdgeThreshold;
    
    // �԰������򲻽��д������ֵ
    // 0.0833 - Ĭ��
    // 0.0625 - �Կ�
    // 0.0312 - ����
    float g_QualityEdgeThresholdMin;
    
    //
    // FXAA_CSʹ��
    //
    
    uint   g_LastQueueIndex;
    uint2  g_StartPixel;
}

SamplerState g_SamplerLinearClamp : register(s0);

//
// FXAA_CSʹ��
//

RWByteAddressBuffer g_WorkCountRW : register(u0);
RWByteAddressBuffer g_WorkQueueRW : register(u1);
RWBuffer<float4> g_ColorQueueRW : register(u2);

ByteAddressBuffer g_WorkCount : register(t0);
ByteAddressBuffer g_WorkQueue : register(t1);
Buffer<float4> g_ColorQueue : register(t2);


#if SUPPORT_TYPED_UAV_LOADS == 1
RWTexture2D<float4> g_ColorOutput : register(u3); // Pass2ʹ��
Texture2D<float4> g_ColorInput : register(t3); // R8G8B8A8_UNORM
float3 FetchColor(int2 st) { return g_Color[st].rgb; }
#else
RWTexture2D<uint> g_ColorOutput : register(u3);
Texture2D<uint> g_ColorInput : register(t3);

uint PackColor(float4 color)
{
    uint R = uint(color.r * 255);
    uint G = uint(color.g * 255) << 8;
    uint B = uint(color.b * 255) << 16;
    uint A = uint(color.a * 255) << 24;
    uint packedColor = R | G | B | A;
    return packedColor;
}

float4 FetchColor(int2 st) 
{
    uint packedColor = g_ColorInput[st];
    return float4((packedColor & 0xFF),
                  ((packedColor >> 8) & 0xFF),
                  ((packedColor >> 16) & 0xFF),
                  ((packedColor >> 24) & 0xFF)) / 255.0f;
}
#endif

// ���ʹ��Ԥ�����luma������Ϊ�����ȡ�����������pass2ʹ��
#if USE_LUMA_INPUT_BUFFER == 1
Texture2D<float> g_Luma : register(t4);
#else
RWTexture2D<float> g_Luma : register(u4);
#endif

//
// FXAAʹ��
//
Texture2D g_TextureInput : register(t5);



//
// ���ȼ���
//


float RGBToLuminance(float3 LinearRGB)
{
    return sqrt(dot(LinearRGB, float3(0.299f, 0.587f, 0.114f)));
}

float RGBToLogLuminance(float3 LinearRGB)
{
    float Luma = dot(LinearRGB, float3(0.212671, 0.715160, 0.072169));
    return log2(1 + Luma * 15) / 4;
}

#endif
