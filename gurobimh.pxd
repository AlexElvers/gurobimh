from cpython cimport array

cpdef quicksum(iterable)


cdef class VarOrConstr:
    cdef int index
    cdef Model model


cdef class Var(VarOrConstr):
    pass


cdef class Constr(VarOrConstr):
    pass


cdef class LinExpr:
    cdef int length
    cdef list vars
    cdef array.array coeffs
    cdef double constant
    cdef LinExpr _copy(self)
    @staticmethod
    cdef void addInplace(LinExpr first, other)
    cdef void subtractInplace(LinExpr first, other)


cdef class Model:
    cdef GRBmodel *model
    cdef int error
    cdef dict attrs
    cdef list _vars
    cdef list _constrs
    cdef list _varsAddedSinceUpdate
    cdef list _varsRemovedSinceUpdate
    cdef list _constrsAddedSinceUpdate
    cdef list _constrsRemovedSinceUpdate
    cdef bint needUpdate
    cdef object callbackFn
    cdef void *cbData
    cdef int cbWhere
    cdef getElementAttr(self, char* key, int element)
    cdef int setElementAttr(self, char* key, int element, value) except -1
    cdef array.array _varInds
    cdef array.array _varCoeffs
    cdef dict _leDct
    cdef int _compressLinExpr(self, LinExpr expr) except -1
    cpdef addVar(self, double lb=?, double ub=?, double obj=?, char vtype=?, name=?)
    cpdef addConstr(self, lhs, char sense, rhs, name=?)
    cdef fastAddConstr(self, double[:] coeffs, list vars, char sense, double rhs, name=?)
    cpdef setObjective(self, expression, sense=*)
    cpdef terminate(self)
    cpdef getVars(self)
    cpdef getConstrs(self)
    cpdef remove(self, VarOrConstr what)
    cpdef update(self)
    cpdef optimize(self, callback=?)
    cpdef cbGet(self, int what)
    cpdef write(self, filename)


cdef extern from 'gurobi_c.h':
    ctypedef struct GRBenv:
        pass
    ctypedef struct GRBmodel:
        pass
    const char GRB_BINARY, GRB_CONTINUOUS, GRB_INTEGER
    const char GRB_EQUAL, GRB_LESS_EQUAL, GRB_GREATER_EQUAL

    const char *GRB_INT_ATTR_MODELSENSE
    const char *GRB_INT_ATTR_NUMCONSTRS
    const char *GRB_INT_ATTR_NUMVARS
    const char *GRB_INT_ATTR_STATUS

    const char *GRB_DBL_ATTR_ITERCOUNT
    const char *GRB_DBL_ATTR_NODECOUNT
    const char *GRB_DBL_ATTR_SLACK
    const char *GRB_DBL_ATTR_LB
    const char *GRB_DBL_ATTR_UB
    const char *GRB_DBL_ATTR_OBJ
    const char *GRB_DBL_ATTR_X
    const char *GRB_DBL_ATTR_OBJVAL
    const char *GRB_DBL_ATTR_OBJCON
    const char *GRB_DBL_ATTR_START


    const char *GRB_STR_ATTR_CONSTRNAME
    const char *GRB_STR_ATTR_VARNAME

    const char *GRB_INT_PAR_METHOD
    const char *GRB_INT_PAR_MIPFOCUS
    const char *GRB_INT_PAR_THREADS
    const char *GRB_INT_PAR_OUTPUTFLAG
    const char *GRB_INT_PAR_PREPASSES
    const char *GRB_INT_PAR_PRESOLVE

    const int GRB_MAXIMIZE, GRB_MINIMIZE, GRB_INFEASIBLE, GRB_OPTIMAL, GRB_INTERRUPTED, \
        GRB_INF_OR_UNBD, GRB_UNBOUNDED
    const double GRB_INFINITY
    const int GRB_CB_POLLING, GRB_CB_PRESOLVE, GRB_CB_SIMPLEX, GRB_CB_MIP, GRB_CB_MIPSOL, \
        GRB_CB_MIPNODE, GRB_CB_MESSAGE, GRB_CB_BARRIER
    # callback codes
    const int GRB_CB_MIPNODE_OBJBST

    const int GRB_ERROR_CALLBACK

    void GRBversion (int *majorP, int *minorP, int *technicalP)
    GRBenv* GRBgetenv(GRBmodel *)
    int GRBloadenv(GRBenv **envP, const char *logfilename)
    int GRBnewmodel (GRBenv *, GRBmodel **modelP, const char *Pname, int numvars, double *obj,
                     double *lb, double *ub, char *vtype, const char **varnames )
    int GRBreadmodel(GRBenv*, const char* filename, GRBmodel **modelP)
    int GRBresetmodel (GRBmodel *)
    int GRBfreemodel (GRBmodel *)
    int GRBaddvar (GRBmodel *, int numnz, int *vind, double *vval, double obj, double lb,
                   double ub, char vtype, const char *varname )
    int GRBsetintattr (GRBmodel *, const char *attrname, int newvalue)
    int GRBgetintattr (GRBmodel *, const char *attrname, int *valueP)
    int GRBgetdblattr (GRBmodel *, const char *attrname, double *valueP)
    int GRBsetdblattr (GRBmodel *, const char *attrname, double newvalue)
    int GRBsetdblattrelement (GRBmodel *, const char *attrname, int element, double newvalue)
    int GRBgetdblattrelement (GRBmodel *, const char *attrname, int element, double *valueP)
    int GRBgetintattrelement (GRBmodel *, const char *attrname, int element, int *valueP)
    int GRBgetstrattrelement (GRBmodel *, const char *attrname, int element, char **valueP)
    int GRBsetstrattrelement (GRBmodel *, const char *attrname, int element, char *value)
    int GRBsetdblattrarray (GRBmodel *, const char *attrname, int start, int len, double *values)
    int GRBgetdblattrarray (GRBmodel *, const char *attrname, int start, int len, double *values)
    int GRBsetintparam (GRBenv *, const char *paramname, int newvalue)
    int GRBsetdblparam (GRBenv *, const char *paramname, double newvalue)
    int GRBupdatemodel (GRBmodel *)
    int GRBaddconstr (GRBmodel *, int numnz, int *cind, double *cval, char sense, double rhs, const char *constrname)
    int GRBdelconstrs (GRBmodel *, int numdel, int *ind)
    int GRBchgcoeffs (GRBmodel *, int numchgs, int *cind, int *vind, double *val)
    int GRBdelvars (GRBmodel *, int numdel, int *ind)
    int GRBoptimize (GRBmodel *)
    int GRBsetcallbackfunc (GRBmodel *, int	(*cb)(GRBmodel *model, void *cbdata, int where, void *usrdata),
  	  	void *usrdata)
    int GRBcbget(void *cbdata, int where, int what, void *resultP)
    void GRBterminate (GRBmodel *)
    int GRBwrite(GRBmodel *, const char *filename)