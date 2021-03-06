# ------------------- #
# Numeric model types #
# ------------------- #

immutable Options{TG<:Union{Void,AbstractGrid}}
    grid::TG
    other::Dict{Symbol,Any}  # TODO: shouldn't need. Just keeps stuff around
end

function Options(sm::AbstractSymbolicModel, calib::ModelCalibration)
    # numericize options
    _options = eval_with(calib, deepcopy(sm.options))

    if haskey(_options, :grid)
        # pop! grid off _options so _options becomes _other
        grid = _build_grid(pop!(_options, :grid), calib)
    else
        grid = nothing
    end
    Options(grid, _options)
end


# Not clear whether we still want Texog, to parameterize the model type.
immutable NumericModel{ID,Texog} <: ANM{ID}
    symbolic::SymbolicModel{ID}
    symbols::OrderedDict{Symbol,Array{Symbol,1}}
    calibration::ModelCalibration
    exogenous::Texog
    options::Options
    name::String
    filename::String
    factories::Dict{Symbol,FunctionFactory}
end


_numeric_mod_type{ID}(::ASM{ID}) = NumericModel{ID}

Base.convert(::Type{SymbolicModel}, m::NumericModel) = m.symbolic

function NumericModel{ID}(sm::SymbolicModel{ID}; print_code::Bool=false)
    # compile all equations
    recipe = RECIPES[:dtcc]
    numeric_mod = _numeric_mod_type(sm)

    factories = Dict{Symbol,FunctionFactory}()

    # compile equations
    for func_nm in keys(sm.equations)
        # extract spec from recipe
        spec = recipe[:specs][func_nm]

        # get expressions from symbolic model
        exprs = sm.equations[func_nm]
        bang_func_nm = Symbol(string(func_nm), "!")

        if length(exprs) == 0
            msg = "Model did not specify functions of type $(func_nm)"
            code = quote
                function $(func_nm)(::$(numeric_mod), args...)
                    error($msg)
                end

                function $(bang_func_nm)(::$(numeric_mod), args...)
                    error($msg)
                end
            end
        else
            ff = FunctionFactory(sm, func_nm)
            code = make_method(ff)
            factories[func_nm] = ff
        end

        print_code && println(code)
        eval(Dolo, code)
    end

    # get numerical calibration and options
    calib = ModelCalibration(sm)
    options = Options(sm, calib)

    exog = _build_exogenous_entry(sm.exogenous, calib)
    NumericModel(sm, sm.symbols, calib, exog, options, sm.name, sm.filename, factories)
end

# ------------- #
# Other methods #
# ------------- #

filename(m::AbstractModel) = m.filename
name(m::AbstractModel) = m.name
