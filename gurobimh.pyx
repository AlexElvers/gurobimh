# -*- coding: utf-8 -*-
# cython: boundscheck=False
# cython: nonecheck=False
# cython: wraparound=False
# Copyright 2015 Michael Helmling
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation

from __future__ import division, print_function
from numbers import Number
from cpython cimport array as c_array
from array import array
# somewhat ugly hack: attribute getters/setters use this special return value to indicate a python
# exception; saves us from having to return objects while still allowing error handling
DEF ERRORCODE = -987654321
class GurobiError(Exception):
    pass


#  we create one master environment used in all models
cdef GRBenv *masterEnv = NULL
cdef int _error = GRBloadenv(&masterEnv, NULL)
if _error:
    raise GurobiError('Loading Gurobi environment failed: error code {}'.format(_error))


def read(fname):
    """Read model from file; *fname* may be bytes or unicode type."""
    cdef int error
    cdef GRBmodel *cModel
    cdef Model model
    error = GRBreadmodel(masterEnv, _chars(fname), &cModel)
    if error:
        raise GurobiError('Unable to read model from file: {}'.format(error))
    model = Model(_create=False)
    model.model = cModel
    for i in range(model.NumVars):
        model._vars.append(Var(model, i))
    for i in range(model.NumConstrs):
        model._constrs.append(Constr(model, i))
    return model



cpdef quicksum(iterable):
    """Create LinExpr consisting of the parts of *iterable*. Elements in the iterator must be either
    Var or LinExpr objects."""
    cdef LinExpr result = LinExpr()
    for element in iterable:
        result += element
    return result


cdef dict CallbackTypes = {}

cdef class CallbackClass:
    """Singleton class for callback constants"""
    cdef:
        readonly int MIPNODE
        readonly int MIPNODE_OBJBST

    def __init__(self):
        self.MIPNODE = GRB_CB_MIPNODE
        self.MIPNODE_OBJBST = GRB_CB_MIPNODE_OBJBST
        CallbackTypes[self.MIPNODE] = int
        CallbackTypes[self.MIPNODE_OBJBST] = float



# === ATTRIBUTES AND PARAMETERS ===
#
# model attrs
cdef list IntAttrs = [b'NumConstrs', b'NumVars', b'ModelSense']
cdef list StrAttrs = [b'ModelName']
cdef list DblAttrs = [b'ObjCon']
cdef list CharAttrs = []
# var attrs
StrAttrs += [b'VarName']
DblAttrs += [b'LB', b'UB', b'Obj', b'Start']
# constraint attrs
DblAttrs += [b'RHS']
StrAttrs += [b'ConstrName']
CharAttrs += [b'Sense']
# solution attrs
IntAttrs += [b'Status']
DblAttrs += [b'ObjVal', b'MIPGap', b'IterCount', b'NodeCount']
# var attrs for current solution
DblAttrs += [b'X']
# constr attr for current solution
DblAttrs += [b'Pi', b'Slack']

cdef set IntAttrsLower  = set(a.lower() for a in IntAttrs)
cdef set DblAttrsLower  = set(a.lower() for a in DblAttrs)
cdef set StrAttrsLower  = set(a.lower() for a in StrAttrs)
cdef set CharAttrsLower = set(a.lower() for a in CharAttrs)

class AttrConstClass:
    """Singleton class for attribute name constants"""
for attr in IntAttrs + StrAttrs + DblAttrs + CharAttrs:
    setattr(AttrConstClass, attr, attr)

# termination
cdef list IntParams = [b'CutOff', b'TimeLimit']
cdef list DblParams = []
cdef list StrParams = []
# tolerances
DblParams += [b'FeasibilityTol', b'IntFeasTol', b'MIPGap', b'MIPGapAbs', b'OptimalityTol']
# simplex
IntParams += [b'Method']
# MIP
IntParams += [b'MIPFocus']
# cuts
IntParams += [b'CutPasses']
# other
IntParams += [b'OutputFlag', b'PrePasses', b'Presolve', b'Threads']
StrParams += [b'LogFile']
DblParams += [b'TuneTimeLimit']

cdef set IntParamsLower = set(a.lower() for a in IntParams)
cdef set DblParamsLower = set(a.lower() for a in DblParams)
cdef set StrParamsLower = set(a.lower() for a in StrParams)


class ParamConstClass:
    """Singleton class for parameter name constants"""
for param in IntParams + StrParams + DblParams:
    setattr(ParamConstClass, attr, attr)

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
            return GRB_INFINITY

    def __init__(self):
        self.BINARY = GRB_BINARY
        self.CONTINUOUS = GRB_CONTINUOUS
        self.INTEGER = GRB_INTEGER
        self.OPTIMAL = GRB_OPTIMAL
        self.INF_OR_UNBD = GRB_INF_OR_UNBD
        self.UNBOUNDED = GRB_UNBOUNDED
        self.LESS_EQUAL = GRB_LESS_EQUAL
        self.EQUAL = GRB_EQUAL
        self.GREATER_EQUAL = GRB_GREATER_EQUAL
        self.MAXIMIZE = GRB_MAXIMIZE
        self.MINIMIZE = GRB_MINIMIZE
        self.callback = self.Callback = CallbackClass()
        self.Param = self.param = ParamConstClass
        self.Attr = self.attr = AttrConstClass

GRB = GRBcls()


class Gurobicls:
    """Emulate gurobipy.gorubi."""
    def version(self):
        cdef int major, minor, tech
        GRBversion(&major, &minor, &tech)
        return major, minor, tech


gurobi = Gurobicls()


cdef class VarOrConstr:
    """Super class vor Variables and Constants. Identified by their index and a pointer to the
    model object.
    """
    #TODO: model should be weak-referecned as in gurobipy

    def __cinit__(self, Model model, int index):
        self.model = model
        self.index = index

    def __getattr__(self, key):
        if self.index < 0:
            raise '{} not yet added to the model'.format(self.__class__.__name__)
        return self.model.getElementAttr(_chars(key), self.index)

    def __setattr__(self, key, value):
        if self.index < 0:
            raise '{} not yet added to the model'.format(self.__class__.__name__)
        self.model.setElementAttr(_chars(key), self.index, value)

    def __str__(self):
        ret = '<gurobimh.{} '.format(type(self).__name__)
        if self.index == -1:
            return ret + '*Awaiting Model Update*>'
        elif self.index == -2:
            return ret + '(Removed)>'
        elif self.index == -3:
            return ret +'*removed*>'
        else:
            return ret + '{}>'.format(self.VarName if isinstance(self, Var) else self.ConstrName)

    def __repr__(self):
        return str(self)


cdef class Var(VarOrConstr):

    def __add__(self, other):
        cdef LinExpr result = LinExpr(self)
        LinExpr.addInplace(result, other)
        return result

    def __mul__(self, other):
        return LinExpr(other, self)

    # explicit getters for time-critical attributes (speedup avoiding __getattr__)
    property X:
        def __get__(self):
            return self.model.getElementDblAttr('X', self.index)

    def __richcmp__(self, other, int op):
        if op == 2: # __eq__
            return TempConstr(LinExpr(self), GRB_EQUAL, LinExpr(other))
        elif op == 1: # __leq__
            return TempConstr(LinExpr(self), GRB_LESS_EQUAL, LinExpr(other))
        elif op == 5: # __geq__
            return TempConstr(LinExpr(self), GRB_GREATER_EQUAL, LinExpr(other))
        raise NotImplementedError()


cdef class Constr(VarOrConstr):
    pass



cdef char* _chars(s):
    """Convert input string to bytes, no matter if *s* is unicode or bytestring"""
    if isinstance(s, unicode):
        # encode to the specific encoding used inside of the module
        s = (<unicode>s).encode('utf8')
    return s


cdef int callbackFunction(GRBmodel *model, void *cbdata, int where, void *userdata):
    """Used for GRBsetcallbackfunc to emulate gurobipy's behaviour"""
    cdef Model theModel = <Model>userdata
    theModel.cbData = cbdata
    theModel.cbWhere = where
    try:
        theModel.callbackFn(theModel, where)
    except Exception as e:
        return GRB_ERROR_CALLBACK
    return 0


cdef class Model:

    def __init__(self, name='', _create=True):

        self.attrs = {}
        self._vars = []
        self._constrs = []
        self._varsAddedSinceUpdate = []
        self._varsRemovedSinceUpdate = []
        self._constrsAddedSinceUpdate = []
        self._constrsRemovedSinceUpdate = []
        self._varInds = array('i', [0]*25)
        self._varCoeffs = array('d', [0]*25)
        self.needUpdate = False
        self.callbackFn = None
        self._leDct = {}
        if _create:
            self.error = GRBnewmodel(masterEnv, &self.model, _chars(name),
                                     0, NULL, NULL, NULL, NULL, NULL)
            if self.error:
                raise GurobiError('Error creating model: {}'.format(self.error))

    def setParam(self, param, value):
        cdef bytes lParam
        if isinstance(param, unicode):
            param = (<unicode>param).encode('utf8')
        lParam = param.lower()
        if lParam in DblParamsLower:
            self.error = GRBsetdblparam(GRBgetenv(self.model), lParam, <double>value)
        elif lParam in IntParamsLower:
            self.error = GRBsetintparam(GRBgetenv(self.model), lParam, <int>value)
        else:
            raise GurobiError('Parameter {} not implemented or unknown'.format(param))
        if self.error:
            raise GurobiError('Error setting parameter: {}'.format(self.error))


    def __setattr__(self, key, value):
        if key[0] == '_':
            self.attrs[key] = value
        else:
            raise NotImplementedError()

    def __getattr__(self, attr):
        cdef int intValue
        cdef double dblValue
        cdef bytes lAttr = _chars(attr).lower()
        if lAttr in IntAttrsLower:
            return self.getIntAttr(attr)
        elif lAttr in DblAttrsLower:
            return self.getDblAttr(attr)
        elif attr[0] == '_':
            return self.attrs[attr]
        else:
            raise GurobiError('Unknown model attribute: {}'.format(attr))

    cdef int getIntAttr(self, char *attr) except ERRORCODE:
        cdef int value
        self.error = GRBgetintattr(self.model, attr, &value)
        if self.error:
            raise GurobiError('Error retrieving int attribute: {}'.format(self.error))
        return value

    cdef double getDblAttr(self, char *attr) except ERRORCODE:
        cdef double value
        self.error = GRBgetdblattr(self.model, attr, &value)
        if self.error:
            raise GurobiError('Error retrieving double attribute: {}'.format(self.error))
        return value

    cdef double getElementDblAttr(self, char *attr, int element) except ERRORCODE:
        """Very fast retrieval of int attributes. Only use when it is ensured that *attr* is a
        valid attribute name!
        """
        cdef double value
        self.error = GRBgetdblattrelement(self.model, attr, element, &value)
        if self.error:
            raise GurobiError('Error retrieving int element attr: {}'.format(self.error))
        return value

    cdef getElementAttr(self, char *attr, int element):
        cdef int intValue
        cdef double dblValue
        cdef char *strValue
        cdef bytes lAttr = attr.lower()
        if lAttr in DblAttrsLower:
            self.error = GRBgetdblattrelement(self.model, lAttr, element, &dblValue)
            if self.error:
                raise GurobiError('Error retrieving dbl attr: {}'.format(self.error))
            return dblValue
        elif lAttr in IntAttrsLower:
            self.error = GRBgetintattrelement(self.model, lAttr, element, &intValue)
            if self.error:
                raise GurobiError('Error retrieving int attr: {}'.format(self.error))
            return intValue
        if lAttr in StrAttrsLower:
            self.error = GRBgetstrattrelement(self.model, lAttr, element, &strValue)
            if self.error:
                raise GurobiError('Error retrieving str attr: {}'.format(self.error))
            return str(strValue)

        else:
            raise GurobiError("Unknown attribute '{}'".format(attr))

    cdef int setElementAttr(self, char *attr, int element, newValue) except -1:
        cdef bytes lAttr = attr.lower()
        if lAttr in StrAttrsLower:
            self.error = GRBsetstrattrelement(self.model, lAttr, element, <const char*>newValue)
            if self.error:
                raise GurobiError('Error setting str attr: {}'.format(self.error))
        elif lAttr in DblAttrsLower:
            self.error = GRBsetdblattrelement(self.model, lAttr, element, <double>newValue)
            if self.error:
                raise GurobiError('Error setting double attr: {}'.format(self.error))
        else:
            raise GurobiError('Unknonw attribute {}'.format(attr))

    # explicit getters for time-critical attributes (speedup avoiding __getattr__)
    property NumConstrs:
        def __get__(self):
            return self.getIntAttr(b'numconstrs')

    property NumVars:
        def __get__(self):
            return self.getIntAttr(b'numvars')


    cpdef addVar(self, double lb=0, double ub=GRB_INFINITY, double obj=0.0,
               char vtype=GRB_CONTINUOUS, name=''):
        cdef Var var
        if isinstance(name, unicode):
            name = name.encode('utf8')
        self.error = GRBaddvar(self.model, 0, NULL, NULL, obj, lb, ub, vtype, name)
        if self.error:
            raise GurobiError('Error creating variable: {}'.format(self.error))
        var = Var(self, -1)
        self._varsAddedSinceUpdate.append(var)
        self.needUpdate = True
        return var

    cdef int _compressLinExpr(self, LinExpr expr) except -1:
        """Compresses linear expressions by adding up coefficients of variables appearing more than
        once. The resulting compressed expression is stored in self.varInds / self.varCoeffs.
        :returns: Length of compressed expression
        """
        cdef int i, j, lenDct
        cdef double coeff
        cdef Var var
        cdef c_array.array[int] varInds
        cdef c_array.array[double] varCoeffs
        self._leDct.clear()
        for i in range(expr.length):
            var = <Var>expr.vars[i]
            if var.index < 0:
                raise GurobiError('Variable not in model')
            if var.index in self._leDct:
                self._leDct[var.index] += expr.coeffs.data.as_doubles[i]
            else:
                self._leDct[var.index] = expr.coeffs.data.as_doubles[i]
        lenDct = len(self._leDct)
        if len(self._varInds) < lenDct:
            c_array.resize(self._varInds, lenDct)
            c_array.resize(self._varCoeffs, lenDct)
        c_array.zero(self._varCoeffs)
        varInds = self._varInds
        varCoeffs = self._varCoeffs

        for i, (j, coeff) in enumerate(self._leDct.items()):
            varInds[i] = j
            varCoeffs[i] = coeff
        return lenDct

    cpdef addConstr(self, lhs, char sense=-1, rhs=None, name=''):
        cdef LinExpr expr
        cdef int lenDct
        cdef Constr constr
        if isinstance(lhs, TempConstr):
            expr = (<TempConstr>lhs).lhs - (<TempConstr>lhs).rhs
            sense = (<TempConstr>lhs).sense
        else:
            expr = LinExpr(lhs)
            LinExpr.subtractInplace(expr, rhs)
        lenDct = self._compressLinExpr(expr)
        self.error = GRBaddconstr(self.model, lenDct, self._varInds.data.as_ints,
                                  self._varCoeffs.data.as_doubles, sense,
                                  -expr.constant, _chars(name))
        if self.error:
            raise GurobiError('Error adding constraint: {}'.format(self.error))
        constr = Constr(self, -1)
        self._constrsAddedSinceUpdate.append(constr)
        self.needUpdate = True
        return constr

    cdef Constr fastAddConstr(self, double[::1] coeffs, list vars, char sense, double rhs, name=''):
        """Efficiently add constraint circumventing LinExpr generation. *coeffs* and *vars* must
        have the same size (this is not checked!).

        Note: if there are duplicates in *vars*, an error will be thrown.
        """
        cdef int[:] varInds = self._varInds
        cdef int i
        cdef Constr constr
        if len(self._varInds) < coeffs.size:
            c_array.resize(self._varInds, coeffs.size)
            c_array.resize(self._varCoeffs, coeffs.size)
        for i in range(coeffs.size):
            varInds[i] = (<Var>vars[i]).index
        self.error = GRBaddconstr(self.model, coeffs.size, &varInds[0],
                                  &coeffs[0], sense, rhs, _chars(name))
        if self.error:
            raise GurobiError('Error adding constraint: {}'.format(self.error))
        constr = Constr(self, -1)
        self._constrsAddedSinceUpdate.append(constr)
        self.needUpdate = True
        return constr

    cdef Constr fastAddConstr2(self, double[::1] coeffs, int[::1] varInds, char sense, double rhs, name=''):
        """Even faster constraint adding given variable index array. You need to ensure that
        *coeffs* and *varInds* have the same length, otherwise segfaults are likely to occur.
        """
        cdef int i
        cdef Constr constr
        self.error = GRBaddconstr(self.model, coeffs.size, &varInds[0],
                                  &coeffs[0], sense, rhs, _chars(name))
        if self.error:
            raise GurobiError('Error adding constraint: {}'.format(self.error))
        constr = Constr(self, -1)
        self._constrsAddedSinceUpdate.append(constr)
        self.needUpdate = True
        return constr

    cpdef setObjective(self, expression, sense=None):
        cdef LinExpr expr = expression if isinstance(expression, LinExpr) else LinExpr(expression)
        cdef int i, error, length
        cdef Var var
        if sense is not None:
            self.error = GRBsetintattr(self.model, b'ModelSense', <int>sense)
            if self.error:
                raise GurobiError('Error setting objective sense: {}'.format(self.error))
        length = self._compressLinExpr(expr)
        for i in range(length):
            self.error = GRBsetdblattrelement(self.model, b'Obj',
                                              self._varInds.data.as_ints[i],
                                              self._varCoeffs.data.as_doubles[i])
            if self.error:
                raise GurobiError('Error setting objective coefficient: {}'.format(self.error))
        if expr.constant != 0:
            self.error = GRBsetdblattr(self.model, b'ObjCon', expr.constant)
            if self.error:
                raise GurobiError('Error setting objective constant: {}'.format(self.error))
        self.needUpdate = True

    cdef fastSetObjective(self, int start, int len, double[::1] coeffs):
        """Efficient objective function manipulation: sets the coefficients of all variables with
        indices in range(start, start+len) according to *coeffs*, which must at least be of the
        correct length (NOT CHECKED!).
        """
        self.error = GRBsetdblattrarray(self.model, b'Obj', start, len, &coeffs[0])
        if self.error:
            raise GurobiError('Error setting objective function: {}'.format(self.error))
        self.needUpdate = True

    cpdef getVars(self):
        return self._vars[:]

    cpdef getConstrs(self):
        return self._constrs[:]

    cpdef remove(self, VarOrConstr what):
        if what.model is not self:
            raise GurobiError('Item to be removed not in model')
        if what.index >= 0:
            if isinstance(what, Constr):
                self.error = GRBdelconstrs(self.model, 1, &what.index)
                if self.error != 0:
                    raise GurobiError('Error removing constraint: {}'.format(self.error))
                self._constrsRemovedSinceUpdate.append(what.index)
            else:
                self.error = GRBdelvars(self.model, 1, &what.index)
                if self.error:
                    raise GurobiError('Error removing variable: {}'.format(self.error))
                self._varsRemovedSinceUpdate.append(what.index)
            what.index = -2
            self.needUpdate = True

    cpdef update(self):
        cdef int numVars = self.NumVars, numConstrs = self.NumConstrs, i
        cdef VarOrConstr voc
        if not self.needUpdate:
            return
        error = GRBupdatemodel(self.model)
        if error:
            raise GurobiError('Error updating the model: {}'.format(self.error))
        if len(self._varsRemovedSinceUpdate):
            for i in sorted(self._varsRemovedSinceUpdate, reverse=True):
                voc = <Var>self._vars[i]
                voc.index = -3
                del self._vars[i]
                for voc in self._vars[i:]:
                    voc.index -= 1
                numVars -= 1
            self._varsRemovedSinceUpdate = []
        if len(self._constrsRemovedSinceUpdate):
            for i in sorted(self._constrsRemovedSinceUpdate, reverse=True):
                voc = <Constr>self._constrs[i]
                voc.index = -3
                del self._constrs[i]
                for voc in self._constrs[i:]:
                    voc.index -= 1
                numConstrs -= 1
            self._constrsRemovedSinceUpdate = []
        if len(self._varsAddedSinceUpdate):
            for i in range(len(self._varsAddedSinceUpdate)):
                voc = self._varsAddedSinceUpdate[i]
                voc.index = numVars + i
                self._vars.append(voc)
            self._varsAddedSinceUpdate = []
        if len(self._constrsAddedSinceUpdate):
            for i in range(len(self._constrsAddedSinceUpdate)):
                voc = self._constrsAddedSinceUpdate[i]
                voc.index = numConstrs + i
                self._constrs.append(voc)
            self._constrsAddedSinceUpdate = []
        self.needUpdate = False

    cpdef optimize(self, callback=None):
        if callback is not None:
            self.error = GRBsetcallbackfunc(self.model, callbackFunction, <void*>self)
            if self.error:
                raise GurobiError('Error installing callback: {}'.format(self.error))
            self.callbackFn = callback
        self.update()
        self.error = GRBoptimize(self.model)
        self.callbackFn = None
        if self.error:
            raise GurobiError('Error optimizing model: {}'.format(self.error))

    cpdef cbGet(self, int what):
        cdef int intResult
        cdef double dblResult = 0
        if what not in CallbackTypes:
            raise GurobiError('Unknown callback "what" requested: {}'.format(what))
        elif CallbackTypes[what] is int:
            self.error = GRBcbget(self.model, self.cbWhere, what, <void*> &intResult)
            if self.error:
                raise GurobiError('Error calling cbget: {}'.format(self.error))
            return intResult
        elif CallbackTypes[what] is float:
            self.error = GRBcbget(self.cbData, self.cbWhere, what, <void*> &dblResult)
            if self.error:
                raise GurobiError('Error calling cbget: {}'.format(self.error))
            return dblResult
        else:
            raise GurobiError()

    cpdef terminate(self):
        GRBterminate(self.model)


    cpdef write(self, filename):
        if isinstance(filename, unicode):
            filename = filename.encode('utf8')
        self.error = GRBwrite(self.model, filename)
        if self.error:
            raise GurobiError('Error writing model: {}'.format(self.error))

    def __dealloc__(self):
        GRBfreemodel(self.model)


cdef c_array.array dblOne = array('d', [1])


cdef class LinExpr:

    def __init__(self, arg1=0.0, arg2=None):
        cdef int i
        if arg2 is None:
            if isinstance(arg1, Var):
                self.constant = 0
                self.vars =[arg1]
                self.coeffs = c_array.copy(dblOne)
                self.length = 1
                return
            elif isinstance(arg1, Number):
                self.constant = float(arg1)
                self.coeffs = c_array.clone(dblOne, 0, False)
                self.vars = []
                self.length = 0
                return
            elif isinstance(arg1, LinExpr):
                self.vars = (<LinExpr>arg1).vars[:]
                self.coeffs = c_array.copy((<LinExpr>arg1).coeffs)
                self.constant = (<LinExpr>arg1).constant
                self.length = len(self.coeffs)
                return
            else:
                arg1, arg2 = zip(*arg1)
        if isinstance(arg1, Var):
            self.vars = [arg1]
            self.coeffs = c_array.clone(dblOne, 1, False)
            self.coeffs.data.as_doubles[0] = arg2
            self.constant = 0
            self.length = 1
        else:
            self.length = len(arg1)
            self.coeffs = c_array.clone(dblOne, self.length, False)
            for i in range(self.length):
                self.coeffs.data.as_doubles[i] = arg1[i]
            self.vars = list(arg2)
            self.constant = 0

    @staticmethod
    cdef int addInplace(LinExpr first, other) except -1:
        cdef LinExpr _other
        if isinstance(other, LinExpr):
            _other = other
            first.vars += _other.vars
            c_array.extend(first.coeffs, _other.coeffs)
            first.constant += _other.constant
            first.length += _other.length
        elif isinstance(other, Var):
            first.vars.append(other)
            c_array.resize_smart(first.coeffs, len(first.coeffs) + 1)
            first.coeffs.data.as_doubles[len(first.coeffs)-1] = 1
            first.length += 1
        else:
            first.constant += <double>other

    @staticmethod
    cdef int subtractInplace(LinExpr first, other) except -1:
        cdef LinExpr _other
        cdef int origLen = len(first.coeffs)
        cdef int i
        if isinstance(other, LinExpr):
            _other = other
            first.vars += _other.vars
            c_array.extend(first.coeffs, _other.coeffs)
            for i in range(origLen, len(first.coeffs)):
                first.coeffs.data.as_doubles[i] *= -1
            first.constant -= _other.constant
            first.length += _other.length
        elif isinstance(other, Var):
            first.vars.append(other)
            c_array.resize_smart(first.coeffs, len(first.coeffs) + 1)
            first.coeffs.data.as_doubles[len(first.coeffs) - 1] = -1
            first.length += 1
        else:
            first.constant -= <double>other

    cdef LinExpr _copy(LinExpr self):
        cdef LinExpr result = LinExpr(self.constant)
        result.vars = self.vars[:]
        result.coeffs = c_array.copy(self.coeffs)
        result.length = self.length
        return result

    def __add__(LinExpr self, other):
        cdef LinExpr result = self._copy()
        LinExpr.addInplace(result, other)
        return result

    def __sub__(LinExpr self, other):
        cdef LinExpr result = self._copy()
        LinExpr.subtractInplace(result, other)
        return result

    def __isub__(LinExpr self, other):
        LinExpr.subtractInplace(self, other)
        return self

    def __iadd__(LinExpr self, other):
        LinExpr.addInplace(self, other)
        return self

    def __richcmp__(self, other, int op):
        if op == 2: # __eq__
            return TempConstr(self, GRB_EQUAL, LinExpr(other))
        elif op == 1: # __leq__
            return TempConstr(self, GRB_LESS_EQUAL, LinExpr(other))
        elif op == 5: # __geq__
            return TempConstr(self, GRB_GREATER_EQUAL, LinExpr(other))
        raise NotImplementedError()

    def __repr__(self):
        return ' + '.join('{}*{}'.format(c, v) for c, v in zip(self.coeffs, self.vars)) + ' + {}'.format(self.constant)

cdef class TempConstr:

    def __init__(self, lhs, char sense, rhs):
        self.lhs = lhs if isinstance(lhs, LinExpr) else LinExpr(lhs)
        self.rhs = rhs if isinstance(rhs, LinExpr) else LinExpr(rhs)
        self.sense = sense