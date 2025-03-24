using DataFrames,CSV,GLM,Plots,Statistics,Turing,Random,StatsPlots,CategoricalArrays
using GeoJSON,GeoInterface,ArchGDAL


function parse_coordinates(coord_str::Union{Missing, AbstractString})
    # Return missing if the input is missing
    ismissing(coord_str) && return missing
    
    # Remove parentheses and split by comma
    stripped = replace(coord_str, r"[()]" => "")
    parts = split(stripped, ",")
    
    # Ensure we have exactly two parts
    length(parts) != 2 && return missing
    
    # Try to parse as floats, handling potential errors
    try
        lat = parse(Float64, strip(parts[1]))
        lon = parse(Float64, strip(parts[2]))
        return (lat, lon)
    catch e
        @warn "Failed to parse coordinates from: $coord_str"
        return missing
    end
end

# Example usage with a DataFrame
function parse_df_coordinates!(df, column_name::Symbol)
    # Create a new column with parsed coordinates
    new_col_name = Symbol(string(column_name, "_parsed"))
    df[!, new_col_name] = parse_coordinates.(df[!, column_name])
    return df
end



Random.seed!(1234)

fc = GeoJSON.read("housing_production/HISTORICAL_NhoodConservationDist.geojson")

ncd = DataFrame(fc)

df.geometry[1]

lat,long = 42.3734,-71.0819

point = GeoInterface.Point([long, lat])


point_geom = ArchGDAL.createpoint(GeoInterface.coordinates(point)...)

polygons = []
for geom in df.geometry
    coords = GeoInterface.coordinates(geom)
    poly_geom = ArchGDAL.createpolygon(coords[1])
    push!(polygons,poly_geom)
end

points = [ArchGDAL.createpoint(GeoInterface.coordinates(GeoInterface.Point(lon,lat))) for (lat,lon) in zip(housing.latitude,housing.longitude)]

simplified = combine(groupby(housing,:gisid),:condition_yearbuilt => first,:IsNCD => first,:NCD => first,:saledate => first)

housing = CSV.read("housing_production/Housing_Starts_1996_-_Present_20250321.csv",DataFrame)


parse_df_coordinates!(housing, :Location)
subset!(housing,:Location_parsed => x -> .!ismissing.(x),"Net Change in Units" => x -> .!ismissing.(x))

points = [ArchGDAL.createpoint(GeoInterface.coordinates(GeoInterface.Point(lon,lat))) for (lat,lon) in housing.Location_parsed]


IsNCD = []
NCD = []
for point in points
    t = [false,""]
    for (i,poly) in enumerate(polygons)
        if ArchGDAL.within(point,poly)
            t = [true,ncd.NAME[i]]
            break
        end
    end
    push!(IsNCD,t[1])
    push!(NCD,t[2])
end 

housing.IsNCD = IsNCD
housing.NCD = NCD
using TuringGLM

df = combine(groupby(housing,["Year Permitted","IsNCD","NCD"]),:"Net Change in Units" => sum => "netchangesum")
df.Decade = map(year -> year === missing ? missing : "$(year ÷ 10 * 10)s", df."Year Permitted")


df.NCD = categorical(df.NCD)
df.IsNCD = categorical(df.IsNCD)
df.IsNCD = categorical(df.IsNCD, levels=[false, true])  # Sets false as reference
df.Decade = categorical(df.Decade)
rename!(df,"Year Permitted" => "Year")

df.netchangesum .= max.(0,df.netchangesum)

fm = @formula(netchangesum ~ IsNCD)

model = turing_model(fm,df;model=NegativeBinomial)
chn = sample(model, NUTS(), 2_000);

plot(chn) 