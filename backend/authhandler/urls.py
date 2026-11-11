from django.urls import path

from . import views

urlpatterns = [
    path('', views.device, name='device'),
    path('deviceredirect', views.deviceredirect, name='deviceredirect'),
    path('register', views.register, name='register'),
    path('unregister', views.unregister, name='unregister'),
    path('refresh', views.refresh, name='refresh'),
    path('apptoken', views.apptoken, name='apptoken'),
    path('getlivestream', views.getlivestream, name='getlivestream'),
    path('getvod', views.getvod, name='getvod'),
]