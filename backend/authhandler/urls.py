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
    path('vodproxy/<str:token>/index.m3u8', views.vodproxy_playlist, name='vodproxy_playlist'),
    path('vodproxy/<str:token>/<str:name>', views.vodproxy_segment, name='vodproxy_segment'),
]