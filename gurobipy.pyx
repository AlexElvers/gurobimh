# -*- coding: utf-8 -*-
# distutils: libraries = ['gurobi60']
# distutils: language = c
# Copyright 2015 Michael Helmling
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation

from __future__ import division, print_function
from numbers import Number
cimport grb
cimport numpy as np
import numpy as np

cdef grb.GRBenv *masterEnv = NULL
_error = grb.GRBloadenv(&masterEnv, NULL)
if _error:
    raise ImportError('Loading Gurobi environment failed: error code {}'.format(_error))


def read(fname):
    """Read model from file; *fname* may be bytes or unicode type."""
    raise NotImplementedError()

cpdef quicksum(iterable):
    """Create LinExpr consisting of the parts of *iterable*. Elements in the iterator must be either
    Var or LinExpr objects."""
    cdef LinExpr result = LinExpr()
    for element in iterable:
        if isinstance(element, Var):
            result._vars.append(element)
            result._coeffs.append(1)
        elif isinstance(element, LinExpr):
            result += <LinExpr>element
        else:
            assert isinstance(element, Number)
            result._constant += <double>element
    return result


cdef class Callbackcls:
    cdef:
        readonly int MIPNODE
        readonly int MIPNODE_OBJBST

    def __init__(self):
        self.MIPNODE = grb.GRB_CB_MIPNODE
        self.MIPNODE_OBJBST = grb.GRB_CB_MIP_OBJBST


cdef class AttrConstClass:

    cdef:
        readonly char* ModelSense
        readonly char* NumConstrs
        readonly char* NumVars
        readonly char* Status

        readonly char* IterCount
        readonly char* Obj
        readonly char* ObjCon
        readonly char* ObjVal
        readonly char* X

        readonly char *ConstrName

    def __init__(self):
        self.ModelSense = IntAttrs[b'modelsense'] = grb.GRB_INT_ATTR_MODELSENSE
        self.NumConstrs = IntAttrs[b'numconstrs'] = grb.GRB_INT_ATTR_NUMCONSTRS
        self.NumVars = IntAttrs[b'numvars'] = grb.GRB_INT_ATTR_NUMVARS
        self.Status = IntAttrs[b'status'] = grb.GRB_INT_ATTR_STATUS

        self.IterCount = DblAttrs[b'itercount'] = grb.GRB_DBL_ATTR_ITERCOUNT
        self.Obj = DblAttrs[b'obj'] = grb.GRB_DBL_ATTR_OBJ
        self.ObjCon = DblAttrs[b'objcon'] = grb.GRB_DBL_ATTR_OBJCON
        self.ObjVal = DblAttrs[b'objval'] = grb.GRB_DBL_ATTR_OBJVAL
        self.X = DblAttrs[b'x'] = grb.GRB_DBL_ATTR_X

        self.ConstrName = StrAttrs[b'constrname'] = grb.GRB_STR_ATTR_CONSTRNAME


cdef class ParamConstClass:

    cdef:
        readonly char* Threads
        readonly char* OutputFlag

    def __init__(self):
        self.Threads = IntParams[b'threads'] = grb.GRB_INT_PAR_THREADS
        self.OutputFlag = IntParams[b'outputflag'] = grb.GRB_INT_PAR_OUTPUTFLAG


cdef dict IntAttrs = {}
cdef dict DblAttrs = {}
cdef dict StrAttrs = {}
cdef dict IntParams = {}
cdef dict DblParams = {}

cdef AttrConstClass cAttr = AttrConstClass()
cdef ParamConstClass cParam = ParamConstClass()


cdef class GRBcls:
    """Dummy class emulating gurobipy.GRB"""

    cdef:
        readonly char BINARY
        readonly char CONTINUOUS
        readonly char INTEGER
        readonly int MAXIMIZE, MINIMIZE, INFEASIBLE, OPTIMAL, INTERRUPTED, \
            INF_OR_UNBD, UNBOUNDED
        readonly char LESS_EQUAL, EQUAL, GREATER_EQUAL
        readonly object Callback, callback, Param, param, Attr, attr
    # workaround: INFINITY class member clashes with gcc macro INFINITY
    property INFINITY:
        def __get__(self):
            return grb.GRB.INFINITY

    def __init__(self):
        self.BINARY = grb.GRB_BINARY
        self.CONTINUOUS = grb.GRB_CONTINUOUS
        self.INTEGER = grb.GRB_INTEGER
        self.OPTIMAL = grb.GRB_OPTIMAL
        self.INF_OR_UNBD = grb.GRB_INF_OR_UNBD
        self.UNBOUNDED = grb.GRB_UNBOUNDED
        self.LESS_EQUAL = grb.GRB_LESS_EQUAL
        self.EQUAL = grb.GRB_EQUAL
        self.GREATER_EQUAL = grb.GRB_GREATER_EQUAL
        self.MAXIMIZE = grb.GRB_MAXIMIZE
        self.MINIMIZE = grb.GRB_MINIMIZE
        self.callback = self.Callback = Callbackcls()
        self.Param = self.param = cParam
        self.Attr = self.attr = cAttr


GRB = GRBcls()


class Gurobicls:

    def version(self):
        cdef int major, minor, tech
        grb.GRBversion(&major, &minor, &tech)
        return major, minor, tech


gurobi = Gurobicls()

cdef class VarOrConstr:

    def __cinit__(self, Model model, int index):
        self.model = model
        self.index = index

    def __getattr__(self, key):
        if self.index < 0:
            return 'Constraint not yet added to the model'
        return self.model._getElementAttr(key, self.index)

    def __str__(self):
        ret = '<gurobimh.{} '.format(type(self).__name__)
        if self.index == -1:
            return ret + '*Awaiting Model Update*>'
        elif self.index == -2:
            return ret + ' (Removed)>'
        elif self.index == -3:
            return ret +' *removed*>'
        else:
            return ret + ' {}>'.format(self.VarName if isinstance(self, Var) else self.ConstrName)


cdef class Var(VarOrConstr):

    def __add__(self, other):
        return LinExpr(self) + other

    def __mul__(self, other):
        return LinExpr(self, other)


cdef class Constr(VarOrConstr):
    pass



cdef char* _chars(s):
    if isinstance(s, unicode):
        # encode to the specific encoding used inside of the module
        s = (<unicode>s).encode('utf8')
    return s


cdef class Model:

    def __init__(self, name=''):
        cdef int error
        cdef char* cName = _chars(name)
        error = grb.GRBnewmodel(masterEnv, &self.model, cName, 0, NULL, NULL, NULL, NULL, NULL)
        if error:
            raise RuntimeError('Error creating model: {}'.format(error))
        self.attrs = {}
        self._vars = []
        self._constrs = []
        self._varsAddedSinceUpdate = []
        self._varsRemovedSinceAdded = []
        self._constrsAddedSinceUpdate = []
        self._constrsRemovedSinceUpdate = []

    def setParam(self, param, value):
        cdef int error
        if isinstance(param, unicode):
            param = (<unicode>param).encode('utf8')
        if param.lower() in DblParams:
            error = grb.GRBsetdblparam(grb.GRBgetenv(self.model), param, <double>value)
        elif param.lower() in IntParams:
            error = grb.GRBsetintparam(grb.GRBgetenv(self.model), param, <int>value)
        else:
            raise NotImplementedError()
        if error:
            raise RuntimeError('Error setting parameter: {}'.format(error))


    def __setattr__(self, key, value):
        self.attrs[key] = value

    def __getattr__(self, key):
        cdef int error, intValue
        cdef double dblValue
        if isinstance(key, unicode):
            key = key.encode('utf8')
        if key.lower() in IntAttrs:
            error = grb.GRBgetintattr(self.model, key.lower(), &intValue)
            if error:
                raise RuntimeError('Error retrieving int attr: {}'.format(error))
            return intValue
        elif key.lower() in DblAttrs:
            error = grb.GRBgetdblattr(self.model, key.lower(), &dblValue)
            if error:
                raise RuntimeError('Error retrieving dbl attr: {}'.format(error))
            return dblValue
        return self.attrs[key]


    cdef _getElementAttr(self, key, int element):
        cdef int error, intValue
        cdef double dblValue
        cdef char *strValue
        if isinstance(key, unicode):
            key = key.encode('utf8')
        if key.lower() in StrAttrs:
            error = grb.GRBgetstrattrelement(self.model, key.lower(), element, &strValue)
            if error:
                raise RuntimeError('Error retrieving str attr: {}'.format(error))
            return str(strValue)
        elif key.lower() in DblAttrs:
            error = grb.GRBgetdblattrelement(self.model, key.lower(), element, &dblValue)
            if error:
                raise RuntimeError('Error retrieving dbl attr: {}'.format(error))
            return dblValue
        else:
            raise RuntimeError("Unknown attribute '{}'".format(key))


    cpdef addVar(self, double lb=0, double ub=grb.GRB_INFINITY, double obj=0.0,
               char vtype=GRB.CONTINUOUS, name=''):
        cdef int error, vind
        cdef Var var
        if isinstance(name, unicode):
            name = name.encode('utf8')
        error = grb.GRBaddvar(self.model, 0, NULL, NULL, obj, lb, ub, vtype, name)
        if error:
            raise RuntimeError('Error creating variable: {}'.format(error))
        var = Var(self, -1)
        self._varsAddedSinceUpdate.append(var)
        return var

    cpdef addConstr(self, lhs, char sense, rhs, name=''):
        cdef np.ndarray[ndim=1, dtype=int] vInd
        cdef LinExpr _lhs = lhs if isinstance(lhs, LinExpr) else LinExpr(lhs)
        cdef np.ndarray[ndim=1, dtype=double] coeffs
        cdef int i
        cdef char* cName = _chars(name)
        cdef Constr constr
        _lhs = _lhs - (rhs if isinstance(rhs, LinExpr) else LinExpr(rhs))
        coeffs = np.array(_lhs._coeffs, dtype=np.double)
        vInd = np.empty(coeffs.size, dtype=np.intc)
        for i in range(vInd.size):
            vInd[i] = (<Var>(_lhs._vars[i])).index
            if vInd[i] < 0:
                raise RuntimeError('Variable not in model')
        grb.GRBaddconstr(self.model, vInd.size, <int*>vInd.data, <double*>coeffs.data, sense,
                         -_lhs._constant, cName)
        constr = Constr(self, -1)
        self._constrsAddedSinceUpdate.append(constr)
        return constr

    cpdef setObjective(self, expression, sense=None):
        cdef LinExpr expr = expression if isinstance(expression, LinExpr) else LinExpr(expression)
        cdef int i, error
        cdef Var var
        if sense is not None:
            error = grb.GRBsetintattr(self.model, grb.GRB_INT_ATTR_MODELSENSE, <int>sense)
            if error:
                raise RuntimeError('Error setting objective sense: {}'.format(error))
        for i in range(len(expr._coeffs)):
            var = <Var>expr._vars[i]
            if var.index < 0:
                raise RuntimeError('Variable not in model')
            error = grb.GRBsetdblattrelement(self.model, grb.GRB_DBL_ATTR_OBJ, var.index,
                                             <double>expr._coeffs[i])
            if error:
                raise RuntimeError('Error setting objective coefficient: {}'.format(error))
        if expr._constant != 0:
            error = grb.GRBsetdblattr(self.model, grb.GRB_DBL_ATTR_OBJCON, expr._constant)
            if error:
                raise RuntimeError('Error setting objective constant: {}'.format(error))

    cpdef getVars(self):
        return self._vars[:]

    cpdef getConstrs(self):
        return self._constrs[:]

    cpdef remove(self, Constr constr):
        raise NotImplementedError()

    cpdef update(self):
        cdef int error, numVars = self.NumVars, numConstrs = self.NumConstrs, i
        cdef Var var
        cdef Constr constr
        error = grb.GRBupdatemodel(self.model)
        if error:
            raise RuntimeError('Error updating the model: {}'.format(error))
        for i in range(len(self._varsAddedSinceUpdate)):
            var = self._varsAddedSinceUpdate[i]
            var.index = numVars + i
            self._vars.append(var)
        self._varsAddedSinceUpdate = []
        for i in range(len(self._constrsAddedSinceUpdate)):
            constr = self._constrsAddedSinceUpdate[i]
            constr.index = numConstrs + i
            self._constrs.append(constr)
        self._constrsAddedSinceUpdate = []

    cpdef optimize(self, callback=None):
        cdef int error
        if callback:
            raise NotImplementedError()
        self.update()
        error = grb.GRBoptimize(self.model)
        if error:
            raise RuntimeError('Error optimizing model: {}'.format(error))

    cpdef terminate(self):
        grb.GRBterminate(self.model)


    cpdef write(self, filename):
        cdef int error
        if isinstance(filename, unicode):
            filename = filename.encode('utf8')
        error = grb.GRBwrite(self.model, filename)
        if error:
            raise RuntimeError('Error writing model: {}'.format(error))

    def __dealloc__(self):
        grb.GRBfreemodel(self.model)


cdef class LinExpr:
    def __init__(self, arg1=0.0, arg2=None):
        self._vars = []
        self._coeffs = []
        self._constant = 0
        if arg2 is None:
            if isinstance(arg1, Var):
                self._vars.append(arg1)
                self._coeffs.append(1.0)
            elif isinstance(arg1, Number):
                self._constant = float(arg1)
            elif isinstance(arg1, LinExpr):
                self._vars = (<LinExpr>arg1)._vars[:]
                self._coeffs = (<LinExpr>arg1)._coeffs[:]
                self._constant = (<LinExpr>arg1)._constant
            else:
                arg1, arg2 = zip(*arg1)
        else:
            if isinstance(arg1, Var):
                self._vars.append(arg1)
                self._coeffs.append(float(arg2))
            else:
                for coeff, var in zip(arg1, arg2):
                    self._vars.append(<Var>var)
                    self._coeffs.append(float(coeff))

    def __add__(LinExpr self, other):
        cdef LinExpr _other, result
        cdef int i
        if not isinstance(other, LinExpr):
            _other = LinExpr(other)
        else:
            _other = <LinExpr>other
        result = LinExpr()
        result._vars = self._vars + _other._vars
        result._coeffs = self._coeffs + _other._coeffs
        result._constant = self._constant + _other._constant
        return result

    def __sub__(LinExpr self, other):
        cdef LinExpr _other, result
        cdef int i
        if not isinstance(other, LinExpr):
            _other = LinExpr(other)
        else:
            _other = <LinExpr>other
        result = LinExpr()
        result._vars = self._vars + _other._vars
        result._coeffs = self._coeffs + [-c for c in _other._coeffs]
        result._constant = self._constant - _other._constant
        return result

    def __iadd__(LinExpr self, other):
        cdef LinExpr _other
        cdef int i
        if not isinstance(other, LinExpr):
            _other = LinExpr(other)
        else:
            _other = <LinExpr>other
        self._vars += _other._vars
        self._coeffs += _other._coeffs
        self._constant += other._constant
        return self
