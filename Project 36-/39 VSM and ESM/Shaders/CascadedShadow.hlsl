
#ifndef CASCADED_SHADOW_HLSL
#define CASCADED_SHADOW_HLSL

#include "ConstantBuffers.hlsl"

// 0: Cascaded Shadow Map
// 1: Variance Shadow Map
// 2: Exponential Shadow Map
// 3: Exponential Variance Shadow Map 2-Component
// 4: Exponential Variance Shadow Map 4-Component
#ifndef SHADOW_TYPE
#define SHADOW_TYPE 1
#endif

// �����ڲ�ͬ����֮�����Ӱֵ��ϡ���shadow maps�Ƚ�С
// ��artifacts����������֮��ɼ���ʱ����Ϊ��Ч
#ifndef BLEND_BETWEEN_CASCADE_LAYERS_FLAG
#define BLEND_BETWEEN_CASCADE_LAYERS_FLAG 0
#endif

// �����ַ���Ϊ��ǰ����ƬԪѡ����ʵļ�����
// Interval-based Selection ����׶�����ȷ���������ƬԪ����Ƚ��бȽ�
// Map-based Selection �ҵ�����������shadow map��Χ�е���С����
#ifndef SELECT_CASCADE_BY_INTERVAL_FLAG
#define SELECT_CASCADE_BY_INTERVAL_FLAG 0
#endif

// ������Ŀ
#ifndef CASCADE_COUNT_FLAG
#define CASCADE_COUNT_FLAG 4
#endif

// ���������£�ʹ��3-4��������������BLEND_BETWEEN_CASCADE_LAYERS_FLAG��
// ���������ڵͶ�PC���߶�PC���Դ���������Ӱ���Լ�����Ļ�ϵش�
// ��ʹ�ø����PCF��ʱ�����Ը��߶�PCʹ�û���ƫ�������ƫ��

Texture2DArray g_TextureShadow : register(t10);
SamplerComparisonState g_SamplerShadowCmp : register(s10);
SamplerState g_SamplerShadow : register(s11);

static const float4 s_CascadeColorsMultiplier[8] =
{
    float4(1.5f, 0.0f, 0.0f, 1.0f),
    float4(0.0f, 1.5f, 0.0f, 1.0f),
    float4(0.0f, 0.0f, 5.5f, 1.0f),
    float4(1.5f, 0.0f, 5.5f, 1.0f),
    float4(1.5f, 1.5f, 0.0f, 1.0f),
    float4(1.0f, 1.0f, 1.0f, 1.0f),
    float4(0.0f, 1.0f, 5.5f, 1.0f),
    float4(0.5f, 3.5f, 0.75f, 1.0f)
};

float Linstep(float a, float b, float v)
{
    return saturate((v - a) / (b - a));
}

// ��[0, amount]�Ĳ��ֹ��㲢��(amount, 1]����ӳ�䵽(0, 1]
float ReduceLightBleeding(float pMax, float amount)
{
    return Linstep(amount, 1.0f, pMax);
}

// �����depth��Ҫ��[0, 1]�ķ�Χ
float2 ApplyEvsmExponents(float depth, float2 exponents)
{
    depth = 2.0f * depth - 1.0f;
    float2 expDepth;
    expDepth.x = exp(exponents.x * depth);
    expDepth.y = -exp(-exponents.y * depth);
    return expDepth;
}

float ChebyshevUpperBound(float2 moments,
                          float receiverDepth,
                          float minVariance,
                          float lightBleedingReduction)
{
    float variance = moments.y - (moments.x * moments.x);
    variance = max(variance, minVariance); // ��ֹ0��
    
    float d = receiverDepth - moments.x;
    float p_max = variance / (variance + d * d);
    
    p_max = ReduceLightBleeding(p_max, lightBleedingReduction);
    
    // �����б�ѩ��
    return (receiverDepth <= moments.x ? 1.0f : p_max);
}

//--------------------------------------------------------------------------------------
// ʹ��PCF�������ͼ��������ɫ�ٷֱ�
//--------------------------------------------------------------------------------------
float CalculatePCFPercentLit(int currentCascadeIndex,
                             float4 shadowTexCoord,
                             float blurSize)
{
    float percentLit = 0.0f;
    // ��ѭ������չ�����������PCF��С�ǹ̶��Ļ�������ʹ������ʱƫ�ƴӶ���������
    for (int x = g_PCFBlurForLoopStart; x < g_PCFBlurForLoopEnd; ++x)
    {
        for (int y = g_PCFBlurForLoopStart; y < g_PCFBlurForLoopEnd; ++y)
        {
            float depthCmp = shadowTexCoord.z;
            // һ���ǳ��򵥵Ľ��PCF���ƫ������ķ�����ʹ��һ��ƫ��ֵ
            // ���ҵ��ǣ������ƫ�ƻᵼ��Peter-panning����Ӱ�ܳ����壩
            // ��С��ƫ���ֻᵼ����Ӱʧ��
            depthCmp -= g_PCFDepthBias;

            // ���任����������ͬ��Ӱͼ�е���Ƚ��бȽ�
            percentLit += g_TextureShadow.SampleCmpLevelZero(g_SamplerShadowCmp,
                float3(
                    shadowTexCoord.x + (float) x * g_TexelSize,
                    shadowTexCoord.y + (float) y * g_TexelSize,
                    (float) currentCascadeIndex
                ),
                depthCmp);
        }
    }
    percentLit /= blurSize;
    return percentLit;
}

//--------------------------------------------------------------------------------------
// VSM���������ͼ��������ɫ�ٷֱ�
//--------------------------------------------------------------------------------------
float CalculateVarianceShadow(float4 shadowTexCoord, 
                              float4 shadowTexCoordViewSpace, 
                              int currentCascadeIndex)
{
    float percentLit = 0.0f;
    
    float2 moments = 0.0f;
    
    // Ϊ�˽��󵼴Ӷ�̬�������������������Ǽ���۲�ռ������ƫ��
    // �Ӷ��õ�ͶӰ����ռ������ƫ��
    float3 shadowTexCoordDDX = ddx(shadowTexCoordViewSpace).xyz;
    float3 shadowTexCoordDDY = ddy(shadowTexCoordViewSpace).xyz;
    shadowTexCoordDDX *= g_CascadeScale[currentCascadeIndex].xyz;
    shadowTexCoordDDY *= g_CascadeScale[currentCascadeIndex].xyz;
    
    moments += g_TextureShadow.SampleGrad(g_SamplerShadow,
                   float3(shadowTexCoord.xy, (float) currentCascadeIndex),
                   shadowTexCoordDDX.xy, shadowTexCoordDDY.xy).xy;
    
    percentLit = ChebyshevUpperBound(moments, shadowTexCoord.z, 0.00001f, g_LightBleedingReduction);
    
    return percentLit;
}

//--------------------------------------------------------------------------------------
// ESM���������ͼ��������ɫ�ٷֱ�
//--------------------------------------------------------------------------------------
float CalculateExponentialShadow(float4 shadowTexCoord,
                                 float4 shadowTexCoordViewSpace,
                                 int currentCascadeIndex)
{
    float percentLit = 0.0f;
    
    float occluder = 0.0f;
    
    float3 shadowTexCoordDDX = ddx(shadowTexCoordViewSpace).xyz;
    float3 shadowTexCoordDDY = ddy(shadowTexCoordViewSpace).xyz;
    shadowTexCoordDDX *= g_CascadeScale[currentCascadeIndex].xyz;
    shadowTexCoordDDY *= g_CascadeScale[currentCascadeIndex].xyz;
    
    occluder += g_TextureShadow.SampleGrad(g_SamplerShadow,
                    float3(shadowTexCoord.xy, (float) currentCascadeIndex),
                    shadowTexCoordDDX.xy, shadowTexCoordDDY.xy).x;
    
    percentLit = saturate(exp(occluder - g_MagicPower * shadowTexCoord.z));
    
    return percentLit;
}

//--------------------------------------------------------------------------------------
// EVSM���������ͼ��������ɫ�ٷֱ�
//--------------------------------------------------------------------------------------
float CalculateExponentialVarianceShadow(float4 shadowTexCoord,
                                         float4 shadowTexCoordViewSpace,
                                         int currentCascadeIndex)
{
    float percentLit = 0.0f;
    
    float2 expDepth = ApplyEvsmExponents(shadowTexCoord.z, float2(g_EvsmPosExp, g_EvsmNegExp));
    float4 moments = 0.0f;
    
    float3 shadowTexCoordDDX = ddx(shadowTexCoordViewSpace).xyz;
    float3 shadowTexCoordDDY = ddy(shadowTexCoordViewSpace).xyz;
    shadowTexCoordDDX *= g_CascadeScale[currentCascadeIndex].xyz;
    shadowTexCoordDDY *= g_CascadeScale[currentCascadeIndex].xyz;
    
    moments += g_TextureShadow.SampleGrad(g_SamplerShadow,
                    float3(shadowTexCoord.xy, (float) currentCascadeIndex),
                    shadowTexCoordDDX.xy, shadowTexCoordDDY.xy);
    
    percentLit = ChebyshevUpperBound(moments.xy, expDepth.x, 0.00001f, g_LightBleedingReduction);
    if (SHADOW_TYPE == 4)
    {
        float neg = ChebyshevUpperBound(moments.zw, expDepth.y, 0.00001f, g_LightBleedingReduction);
        percentLit = min(percentLit, neg);
    }
    
    return percentLit;
}

//--------------------------------------------------------------------------------------
// ������������֮��Ļ���� �� ��Ͻ��ᷢ��������
//--------------------------------------------------------------------------------------
void CalculateBlendAmountForInterval(int currentCascadeIndex,
                                     inout float pixelDepth,
                                     inout float currentPixelsBlendBandLocation,
                                     out float blendBetweenCascadesAmount)
{
    
    //                  pixelDepth
    //           |<-      ->|
    // /-+-------/----------+------/--------
    // 0 N     F[0]               F[i]
    //           |<-blendInterval->|
    // blendBandLocation = 1 - depth/F[0] or
    // blendBandLocation = 1 - (depth-F[0]) / (F[i]-F[0])
    // blendBandLocationλ��[0, g_CascadeBlendArea]ʱ������[0, 1]�Ĺ���
    
    // ������Ҫ���㵱ǰshadow map�ı�Ե�ش��������ｫ�ᵭ������һ������
    // Ȼ�����ǾͿ�����ǰ���뿪�������PCF forѭ��
    float blendInterval = g_CascadeFrustumsEyeSpaceDepths[currentCascadeIndex];
    
    // ��ԭ��Ŀ���ⲿ�ִ������������
    if (currentCascadeIndex > 0)
    {
        int blendIntervalbelowIndex = currentCascadeIndex - 1;
        pixelDepth -= g_CascadeFrustumsEyeSpaceDepths[blendIntervalbelowIndex];
        blendInterval -= g_CascadeFrustumsEyeSpaceDepths[blendIntervalbelowIndex];
    }
    
    // ��ǰ���صĻ�ϵش���λ��
    currentPixelsBlendBandLocation = 1.0f - pixelDepth / blendInterval;
    // blendBetweenCascadesAmount�������յ���Ӱɫ��ֵ
    blendBetweenCascadesAmount = currentPixelsBlendBandLocation / g_CascadeBlendArea;
}

//--------------------------------------------------------------------------------------
// ������������֮��Ļ���� �� ��Ͻ��ᷢ��������
//--------------------------------------------------------------------------------------
void CalculateBlendAmountForMap(float4 shadowMapTexCoord,
                                inout float currentPixelsBlendBandLocation,
                                inout float blendBetweenCascadesAmount)
{
    //   _____________________
    //  |       map[i+1]      |
    //  |                     |
    //  |      0_______0      |
    //  |______| map[i]|______|
    //         |  0.5  |
    //         |_______|
    //         0       0
    // blendBandLocation = min(tx, ty, 1-tx, 1-ty);
    // blendBandLocationλ��[0, g_CascadeBlendArea]ʱ������[0, 1]�Ĺ���
    float2 distanceToOne = float2(1.0f - shadowMapTexCoord.x, 1.0f - shadowMapTexCoord.y);
    currentPixelsBlendBandLocation = min(shadowMapTexCoord.x, shadowMapTexCoord.y);
    float currentPixelsBlendBandLocation2 = min(distanceToOne.x, distanceToOne.y);
    currentPixelsBlendBandLocation =
        min(currentPixelsBlendBandLocation, currentPixelsBlendBandLocation2);
    
    blendBetweenCascadesAmount = currentPixelsBlendBandLocation / g_CascadeBlendArea;
}

//--------------------------------------------------------------------------------------
// ���㼶����ʾɫ���߶�Ӧ�Ĺ���ɫ
//--------------------------------------------------------------------------------------
float4 GetCascadeColorMultipler(int currentCascadeIndex, 
                                int nextCascadeIndex, 
                                float blendBetweenCascadesAmount)
{
    return lerp(s_CascadeColorsMultiplier[nextCascadeIndex], 
                s_CascadeColorsMultiplier[currentCascadeIndex], 
                blendBetweenCascadesAmount);
}

//--------------------------------------------------------------------------------------
// ���㼶����Ӱ
//--------------------------------------------------------------------------------------
float CalculateCascadedShadow(float4 shadowMapTexCoordViewSpace, 
                              float currentPixelDepth,
                              out int currentCascadeIndex,
                              out int nextCascadeIndex,
                              out float blendBetweenCascadesAmount)
{
    float4 shadowMapTexCoord = 0.0f;
    float4 shadowMapTexCoord_blend = 0.0f;
    
    float4 visualizeCascadeColor = float4(0.0f, 0.0f, 0.0f, 1.0f);
    
    float percentLit = 0.0f;
    float percentLit_blend = 0.0f;

    float upTextDepthWeight = 0;
    float rightTextDepthWeight = 0;
    float upTextDepthWeight_blend = 0;
    float rightTextDepthWeight_blend = 0;
         
    int cascadeFound = 0;
    nextCascadeIndex = 1;
    
    float blurSize = g_PCFBlurForLoopEnd - g_PCFBlurForLoopStart;
    blurSize *= blurSize;
    
    //
    // ȷ���������任��Ӱ��������
    //
    
    // ����׶���Ǿ��Ȼ��� �� ʹ����Interval-Based Selection����ʱ
    // ���Բ���Ҫѭ��������
    // �����������currentPixelDepth����������ȷ����׶�������в���
    // Interval-Based Selection
    if (SELECT_CASCADE_BY_INTERVAL_FLAG)
    {
        currentCascadeIndex = 0;
        //                               Depth
        // /-+-------/----------------/----+-------/----------/
        // 0 N     F[0]     ...      F[i]        F[i+1] ...   F
        // Depth > F[i] to F[0] => index = i+1
        if (CASCADE_COUNT_FLAG > 1)
        {
            float4 currentPixelDepthVec = currentPixelDepth;
            float4 cmpVec1 = (currentPixelDepthVec > g_CascadeFrustumsEyeSpaceDepthsData[0]);
            float4 cmpVec2 = (currentPixelDepthVec > g_CascadeFrustumsEyeSpaceDepthsData[1]);
            float index = dot(float4(CASCADE_COUNT_FLAG > 0,
                                     CASCADE_COUNT_FLAG > 1,
                                     CASCADE_COUNT_FLAG > 2,
                                     CASCADE_COUNT_FLAG > 3),
                              cmpVec1) +
                          dot(float4(CASCADE_COUNT_FLAG > 4,
                                     CASCADE_COUNT_FLAG > 5,
                                     CASCADE_COUNT_FLAG > 6,
                                     CASCADE_COUNT_FLAG > 7),
                              cmpVec2);
            index = min(index, CASCADE_COUNT_FLAG - 1);
            currentCascadeIndex = (int) index;
        }
        
        shadowMapTexCoord = shadowMapTexCoordViewSpace * g_CascadeScale[currentCascadeIndex] + g_CascadeOffset[currentCascadeIndex];
    }

    // Map-Based Selection
    if ( !SELECT_CASCADE_BY_INTERVAL_FLAG )
    {
        currentCascadeIndex = 0;
        if (CASCADE_COUNT_FLAG == 1)
        {
            shadowMapTexCoord = shadowMapTexCoordViewSpace * g_CascadeScale[0] + g_CascadeOffset[0];
        }
        if (CASCADE_COUNT_FLAG > 1)
        {
            // Ѱ������ļ�����ʹ����������λ������߽���
            // minBorder < tx, ty < maxBorder
            for (int cascadeIndex = 0; cascadeIndex < CASCADE_COUNT_FLAG && cascadeFound == 0; ++cascadeIndex)
            {
                shadowMapTexCoord = shadowMapTexCoordViewSpace * g_CascadeScale[cascadeIndex] + g_CascadeOffset[cascadeIndex];
                if (min(shadowMapTexCoord.x, shadowMapTexCoord.y) > g_MinBorderPadding
                    && max(shadowMapTexCoord.x, shadowMapTexCoord.y) < g_MaxBorderPadding)
                {
                    currentCascadeIndex = cascadeIndex;
                    cascadeFound = 1;
                }
            }
        }
    }
    
    //
    // ���㵱ǰ������PCF
    // 
    
    visualizeCascadeColor = s_CascadeColorsMultiplier[currentCascadeIndex];
    
    if (SHADOW_TYPE == 0)
        percentLit = CalculatePCFPercentLit(currentCascadeIndex, shadowMapTexCoord, blurSize);
    if (SHADOW_TYPE == 1)
        percentLit = CalculateVarianceShadow(shadowMapTexCoord, shadowMapTexCoordViewSpace, currentCascadeIndex);
    if (SHADOW_TYPE == 2)
        percentLit = CalculateExponentialShadow(shadowMapTexCoord, shadowMapTexCoordViewSpace, currentCascadeIndex);
    if (SHADOW_TYPE >= 3)
        percentLit = CalculateExponentialVarianceShadow(shadowMapTexCoord, shadowMapTexCoordViewSpace, currentCascadeIndex);
    
    //
    // ����������֮����л��
    //
    if (BLEND_BETWEEN_CASCADE_LAYERS_FLAG)
    {
        // Ϊ��һ�������ظ�����ͶӰ��������ļ���
        // ��һ������������������������֮��ģ��
        nextCascadeIndex = min(CASCADE_COUNT_FLAG - 1, currentCascadeIndex + 1);
    }
    
    blendBetweenCascadesAmount = 1.0f;
    float currentPixelsBlendBandLocation = 1.0f;
    if (SELECT_CASCADE_BY_INTERVAL_FLAG)
    {
        if (BLEND_BETWEEN_CASCADE_LAYERS_FLAG && CASCADE_COUNT_FLAG > 1)
        {
            CalculateBlendAmountForInterval(currentCascadeIndex, currentPixelDepth,
                currentPixelsBlendBandLocation, blendBetweenCascadesAmount);
        }
    }
    else
    {
        if (BLEND_BETWEEN_CASCADE_LAYERS_FLAG && CASCADE_COUNT_FLAG > 1)
        {
            CalculateBlendAmountForMap(shadowMapTexCoord,
                currentPixelsBlendBandLocation, blendBetweenCascadesAmount);
        }
    }
    
    if (BLEND_BETWEEN_CASCADE_LAYERS_FLAG && CASCADE_COUNT_FLAG > 1)
    {
        if (currentPixelsBlendBandLocation < g_CascadeBlendArea)
        {
            // ������һ������ͶӰ��������
            shadowMapTexCoord_blend = shadowMapTexCoordViewSpace * g_CascadeScale[nextCascadeIndex] + g_CascadeOffset[nextCascadeIndex];
            
            // �ڼ���֮����ʱ��Ϊ��һ����Ҳ���м���
            if (currentPixelsBlendBandLocation < g_CascadeBlendArea)
            {
                if (SHADOW_TYPE == 0)
                    percentLit_blend = CalculatePCFPercentLit(nextCascadeIndex, shadowMapTexCoord_blend, blurSize);
                if (SHADOW_TYPE == 1)             
                    percentLit_blend = CalculateVarianceShadow(shadowMapTexCoord_blend, shadowMapTexCoordViewSpace, nextCascadeIndex);
                if (SHADOW_TYPE == 2)
                    percentLit_blend = CalculateExponentialShadow(shadowMapTexCoord_blend, shadowMapTexCoordViewSpace, nextCascadeIndex);
                if (SHADOW_TYPE >= 3)
                    percentLit_blend = CalculateExponentialVarianceShadow(shadowMapTexCoord_blend, shadowMapTexCoordViewSpace, nextCascadeIndex);
                
                // ������������PCF���
                percentLit = lerp(percentLit_blend, percentLit, blendBetweenCascadesAmount);
            }
        }
    }

    return percentLit;
}


#endif // CASCADED_SHADOW_HLSL
