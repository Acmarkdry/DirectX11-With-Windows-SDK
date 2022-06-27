
#ifndef PBR_HLSL
#define PBR_HLSL

Texture2D g_AlbedoMap : register(t0);
Texture2D g_NormalMap : register(t1);
Texture2D g_MetallicMap : register(t2);
Texture2D g_RoughnessMap : register(t3);
Texture2D g_AoMap : register(t4);

float3 NormalSampleToWorldSpace(float3 normalMapSample, float3 unitNormalW, float4 tangentW)
{
    // ����ȡ���������е�ÿ��������[0, 1]��ԭ��[-1, 1]
    float3 normalT = 2.0f * normalMapSample - 1.0f;

    // ����λ����������ϵ�����߿ռ�
    float3 N = unitNormalW;
    float3 T = normalize(tangentW.xyz - dot(tangentW.xyz, N) * N); // ʩ����������
    float3 B = cross(N, T);

    float3x3 TBN = float3x3(T, B, N);

    // ��������ͼ�����ķ����������߿ռ�任����������ϵ
    float3 bumpedNormalW = mul(normalT, TBN);

    return bumpedNormalW;
}

float3 NormalSampleToWorldSpace(float3 normalMapSample, float3 unitNormalW, float3 posW, float2 texcoord)
{
    // ����ȡ���������е�ÿ��������[0, 1]��ԭ��[-1, 1]
    float3 normalT = 2.0f * normalMapSample - 1.0f;
    
    // ʹ��ƫ���������ߺ͸�����
    float3 Q1 = ddx_coarse(posW);
    float3 Q2 = ddy_coarse(posW);
    float2 st1 = ddx(texcoord);
    float2 st2 = ddy(texcoord);
    
    float3 N = unitNormalW;
    float3 T = normalize(Q1 * st2.y - Q2 * st2.x);
    float3 B = normalize(cross(N, T));

    float3x3 TBN = float3x3(T, B, N);

    // ��������ͼ�����ķ����������߿ռ�任����������ϵ
    float3 bumpedNormalW = mul(normalT, TBN);

    return bumpedNormalW;
}

// Shlick's approximation of Fresnel
// https://en.wikipedia.org/wiki/Schlick%27s_approximation
float3 Fresnel_Schlick(float3 f0, float3 f90, float x)
{
    return f0 + (f90 - f0) * pow(saturate(1.0f - x), 5.0f);
}

// Burley B. "Physically Based Shading at Disney"
// SIGGRAPH 2012 Course: Practical Physically Based Shading in Film and Game Production, 2012.
float Diffuse_Burley(in float NdotL, in float NdotV, in float LdotH, in float roughness)
{
    float fd90 = 0.5f + 2.f * roughness * LdotH * LdotH;
    return Fresnel_Schlick(1.0f, fd90, NdotL).x * Fresnel_Schlick(1.0f, fd90, NdotV).x;
}

// GGX specular D (normal distribution)
// https://www.cs.cornell.edu/~srm/publications/EGSR07-btdf.pdf
float Specular_D_GGX(in float alpha, in float NdotH)
{
    static const float PI = 3.14159265f;
    static const float EPS = 1e-6f;
    const float alpha2 = alpha * alpha;
    const float lower = (NdotH * NdotH * (alpha2 - 1.0f)) + 1.0f;
    return alpha2 / max(EPS, PI * lower * lower);
}

// Schlick-Smith specular G (visibility) with Hable's LdotH optimization
// http://www.cs.virginia.edu/~jdl/bib/appearance/analytic%20models/schlick94b.pdf
// http://graphicrants.blogspot.se/2013/08/specular-brdf-reference.html
float G_Schlick_Smith_Hable(float alpha, float LdotH)
{
    return rcp(lerp(LdotH * LdotH, 1.0f, alpha * alpha * 0.25f));
}


float G_Schlick_GGX(float NdotV, float k)
{
    return NdotV / lerp(NdotV, 1.0f, k);
}

float G_Smith(float NdotV, float NdotL, float k)
{
    return G_Schlick_GGX(NdotV, k) * G_Schlick_GGX(NdotL, k);
}

// ����΢�����BRDF
//
// roughness:       �ֲڶ�
//
// specularColor:   F0������ - �ǽ���0.04������ʹ��RGB����ģ����ѭUE4
//
//      N - ���淨��
//      V - ��������߷���
//      L - ���շ���
//      H - L��V�İ������
float3 Specular_BRDF(float alpha,
                     float k,
                     float3 specularColor,
                     float NdotV,
                     float NdotL,
                     float HdotV,
                     float NdotH)
{
    // ΢���淨�߷ֲ���
    // \alpha^2 / (\pi (NdotH)^2 (\alpha^2 - 1) + 1)^2 )
    float specular_D = Specular_D_GGX(alpha, NdotH);

    // �����������
    // F_0 + (1 - F_0)(1 - HdotV)^5
    float3 specular_F = Fresnel_Schlick(specularColor, 1.0f, HdotV);

    // ���漸���ڱ���(�ɼ���)
    // NdotV / ( NdotV(1 - k) + k ) * NdotL / ( NdotH(1 - k) + k )
    // k_direct = (\alpha + 1)^2 / 8
    // K_IBL = \alpha^2 / 2
    float specular_G = G_Smith(NdotV, NdotL, k);

    return specular_D * specular_F * specular_G;
}

// �Ա���Ӧ�õ�ʿ�����PBR:
//
// V, N:             ��������߷���ͱ��淨��
//
// numLights:        Number of directional lights.
//
// lightColor[]:     Color and intensity of directional light.
//
// lightDirection[]: Light direction.
float3 AccumulateBRDF(
    float3 V, float3 N,
    int numLights, float3 lightColor[4], float3 lightDirection[4],
    float3 albedo, float roughness, float metallic, float ambientOcclusion)
{
    static const float PI = 3.14159265f;
    static const float EPS = 1e-6f;
    static const float specularCoefficient = 0.04f;
    
    const float NdotV = saturate(dot(N, V));
    
    // �������� - ֻ�зǽ�������������
    const float3 diffuse = lerp(albedo, 0.0f, metallic) / PI;
    // F0 - �Էǽ���ʹ�ù̶�����ֵ
    const float3 F0 = lerp(specularCoefficient, albedo, metallic);

    float alpha = roughness * roughness;
    // k_direct
    float k = (alpha + 1) * (alpha + 1) / 8;
    
    float3 acc_color = 0;
    for (int i = 0; i < numLights; i++)
    {
        // ָ����յ�����
        const float3 L = normalize(-lightDirection[i]);

        // �������
        const float3 H = normalize(L + V);

        const float NdotL = saturate(dot(N, L));
        const float NdotH = saturate(dot(N, H));
        const float HdotV = saturate(dot(H, V));
        // ������ & ����߹���
        
        // ΢���淨�߷ֲ���
        // \alpha^2 / (\pi (NdotH)^2 (\alpha^2 - 1) + 1)^2 )
        float specular_D = Specular_D_GGX(alpha, NdotH);

        // �����������
        // F_0 + (1 - F_0)(1 - HdotV)^5
        float3 specular_F = Fresnel_Schlick(F0, 1.0f, HdotV);

        // ���漸���ڱ���(�ɼ���)
        // NdotV / ( NdotV(1 - k) + k ) * NdotL / ( NdotH(1 - k) + k )
        // k_direct = (\alpha + 1)^2 / 8
        // K_IBL = \alpha^2 / 2
        float specular_G = G_Smith(NdotV, NdotL, k);
        
        float3 specular = specular_D * specular_F * specular_G;
        specular *= rcp(4.0f * NdotV * NdotL + 0.0001f);

        // specularF��ΪkS
        //   lerp(diff, specular, specular_F)
        // = (1 - kS) diff + kS * specular
        acc_color += NdotL * lightColor[i] * lerp(diffuse, specular, specular_F);
    }

    // ��������(������ʹ��env lighting�滻ambient lighting
    float3 ambient = 0.03f * albedo * ambientOcclusion;
    acc_color += ambient;

    return acc_color;
}

#endif // PBR_HLSL
