# Make SQL fun!

module FunSQL

export
    @funsql,
    var"funsql_&&",
    var"funsql_||",
    var"funsql_!",
    var"funsql_==",
    var"funsql_!=",
    var"funsql_===",
    var"funsql_!==",
    var"funsql_>",
    var"funsql_>=",
    var"funsql_<",
    var"funsql_<=",
    var"funsql_+",
    var"funsql_-",
    var"funsql_*",
    var"funsql_/",
    funsql_agg,
    funsql_append,
    funsql_as,
    funsql_asc,
    funsql_avg,
    funsql_between,
    funsql_bind,
    funsql_case,
    funsql_cast,
    funsql_coalesce,
    funsql_concat,
    funsql_count,
    funsql_count_distinct,
    funsql_cross_join,
    funsql_cume_dist,
    funsql_current_date,
    funsql_current_timestamp,
    funsql_define,
    funsql_dense_rank,
    funsql_desc,
    funsql_exists,
    funsql_extract,
    funsql_filter,
    funsql_first_value,
    funsql_from,
    funsql_fun,
    funsql_group,
    funsql_highlight,
    funsql_in,
    funsql_iterate,
    funsql_is_not_null,
    funsql_is_null,
    funsql_join,
    funsql_lag,
    funsql_last_value,
    funsql_lead,
    funsql_left_join,
    funsql_like,
    funsql_limit,
    funsql_max,
    funsql_min,
    funsql_not_between,
    funsql_not_exists,
    funsql_not_in,
    funsql_not_like,
    funsql_nth_value,
    funsql_ntile,
    funsql_order,
    funsql_over,
    funsql_partition,
    funsql_percent_rank,
    funsql_rank,
    funsql_row_number,
    funsql_select,
    funsql_sort,
    funsql_sum,
    funsql_with


using Dates
using PrettyPrinting: PrettyPrinting, pprint, quoteof, tile_expr, literal
using OrderedCollections: OrderedDict, OrderedSet
using Tables
using DBInterface
using LRUCache
using DataAPI

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

"""
Base error class for all errors raised by FunSQL.
"""
abstract type FunSQLError <: Exception
end

include("dissect.jl")
include("quote.jl")
include("dialects.jl")
include("types.jl")
include("catalogs.jl")
include("strings.jl")
include("clauses.jl")
include("nodes.jl")
include("connections.jl")
#include("annotate.jl")
include("resolve.jl")
include("link.jl")
include("translate.jl")
include("serialize.jl")
include("render.jl")
include("reflect.jl")

end
