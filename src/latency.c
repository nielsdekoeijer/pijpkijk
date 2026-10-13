#include <spa/param/latency-utils.h>
#include <spa/param/profiler.h>
#include <spa/pod/iter.h>

/* Zig's C translator cannot emit the variadic inline SPA pod parser. */
int pijpkijk_latency_parse(const struct spa_pod *pod, struct spa_latency_info *info)
{
    return spa_latency_parse(pod, info);
}

int pijpkijk_profiler_clock_parse(const struct spa_pod *pod,
        struct spa_fraction *rate, uint64_t *quantum)
{
    int32_t flags, id;
    const char *name;
    int64_t nsec, position, duration;
    const struct spa_pod_prop *prop = spa_pod_find_prop(pod, NULL, SPA_PROFILER_clock);
    if (prop == NULL)
        return -ENOENT;
    int res = spa_pod_parse_struct(&prop->value,
            SPA_POD_Int(&flags), SPA_POD_Int(&id), SPA_POD_String(&name),
            SPA_POD_Long(&nsec), SPA_POD_Fraction(rate),
            SPA_POD_Long(&position), SPA_POD_Long(&duration));
    if (res < 0)
        return res;
    if (rate->num == 0 || rate->denom == 0 || duration <= 0)
        return -EINVAL;
    *quantum = duration;
    return 0;
}
